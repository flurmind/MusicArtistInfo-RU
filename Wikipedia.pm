package Plugins::MusicArtistInfo::Wikipedia;

use strict;
use utf8;
use Encode qw(decode_utf8 is_utf8);

use HTML::FormatText;
use Text::Levenshtein;
use URI::Escape qw(uri_escape uri_escape_utf8);

use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string cstring);

use Plugins::MusicArtistInfo::Common qw(CAN_IMAGEPROXY validateLanguage);

use constant MIN_REVIEW_SIZE => 50;
use constant PAGE_URL => 'https://%s.wikipedia.org/wiki/%s';
# https://www.mediawiki.org/wiki/API:Search
use constant SEARCH_URL => 'https://%s.wikipedia.org/w/api.php?format=json&action=query&list=search&srsearch=%s&srprop=snippet|categorysnippet'; # params: language, query string
# https://www.mediawiki.org/wiki/API:Get_the_contents_of_a_page#Method_3:_Use_the_TextExtracts_API
use constant FETCH_URL => 'https://%s.wikipedia.org/w/api.php?action=query&prop=extracts&formatversion=2&format=json&pageids=%s&redirects=1'; # params: language, page ID

use constant LOOKUP_URL => 'https://%s.wikipedia.org/w/api.php?action=query&titles=%s&format=json&formatversion=2&prop=categories&cllimit=15&clshow=!hidden';
# we need to localize search terms, but can't read from strings table, as we'd only have the main language, not what might have been requested
my $searchTypes = {
    album => {
        EN    => 'Album',
        RU    => 'альбом',
        ES    => 'Álbum',
        FI    => 'Levy',
        PT    => 'Álbum',
        ZH_CN => '专辑',
    },
    work => {
        CS    => 'Díla',
        DA    => 'Værk',
        DE    => 'Werk',
        EN    => 'work',
        ES    => 'Obra',
        FR    => 'Œuvre',
        HU    => 'Művek',
        NL    => 'Compositie',
        PT    => 'Obra',
        RU    => 'произведение',
        SV    => 'Verk',
        ZH_CN => '作品',
    },
    track => {
        EN    => 'track',
        RU    => 'песня',
    },
};

my $log = logger('plugin.musicartistinfo');
my $prefs = preferences('plugin.musicartistinfo');

sub _rank {
	my $item = shift;
	my ($condition, $value, $message);

	my $condition = shift if scalar @_ == 3;
	my ($value, $message) = @_;

	if ($condition) {
		main::INFOLOG && $log->is_info && $log->info($message);
		$item->{ranking} += $value;
	}

	return $condition;
}

sub getAlbumOrWorkReview {
	my ( $class, $client, $cb, $type, $args ) = @_;
	
	# 1. UTF-8 нормализация (защита от багов кодировки)
	for my $k (qw(artist title album)) {
		next unless defined $args->{$k};
		if ( !Encode::is_utf8($args->{$k}) ) {
			$args->{$k} = Encode::decode_utf8($args->{$k}, Encode::FB_DEFAULT);
		}
	}

	my $lang = validateLanguage($client, $args->{lang});

	main::INFOLOG && $log->is_info && $log->info(
		"Wikipedia getAlbumOrWorkReview: title='$args->{title}' artist='$args->{artist}' lang=$lang"
	);

	my $localizedType = $searchTypes->{$type}->{uc($lang)} || $searchTypes->{$type}->{EN} || $type;
	my $disambigTitle = $args->{title} . ' (' . $localizedType . ')';

	# 2. Безопасное сравнение имени артиста и альбома через нормализацию
	my $isSameName = _normalizeName($args->{title}) eq _normalizeName($args->{artist});
	
	# ------------------------------------------------------------------
	# 1. FIRST TRY:
	# exact disambiguated title
	# ------------------------------------------------------------------

	Plugins::MusicArtistInfo::Common->call(

		sprintf(
			LOOKUP_URL,
			$lang,
			uri_escape_utf8($disambigTitle)
		),

		sub {
			my $lookupResult = shift;

			my $page = eval {
				$lookupResult->{query}{pages}[0]
			};

			if (
				$page
				&& $page->{pageid}
				&& $page->{pageid} > 0
			) {

				main::INFOLOG
					&& $log->is_info
					&& $log->info(
						"Wikipedia direct disambig hit: '$page->{title}' lang=$lang"
					);

				$class->getPage(
					$client,

					sub {
						my $review = shift;

						$review->{review}     = delete $review->{content};
						$review->{reviewText} = delete $review->{contentText};

						$cb->($review);
					},

					{
						title => $page->{title},
						id    => $page->{pageid},
						lang  => $lang,
					}
				);

				return;
			}

			# ----------------------------------------------------------
			# 2. SECOND TRY:
			# plain title
			# only if title != artist
			# ----------------------------------------------------------

			if (!$isSameName) {

				Plugins::MusicArtistInfo::Common->call(

					sprintf(
						LOOKUP_URL,
						$lang,
						uri_escape_utf8($args->{title})
					),

					sub {
						my $lookupResult2 = shift;

						my $page2 = eval {
							$lookupResult2->{query}{pages}[0]
						};
					
						if ($page2 && $page2->{pageid} && $page2->{pageid} > 0) {
							# Проверяем категории: добавлены русские корни для ру-вики
							my @cats = map { lc($_->{title}) } @{$page2->{categories} || []};
							my $looksLikeArtist = grep {
								/\bband\b|\bmusician|\bsinger|\bgroup\b|\brapper\b|\bduo\b|\btrio\b|групп|музыкант|коллектив|исполнител|певец|певиц/i
							} @cats;
							my $looksLikeAlbum = grep {
								/\balbum\b|\bsoundtrack\b|\bep\b|\bsingle\b|альбом|сингл|саундтрек|сборник/i
							} @cats;

							if ($looksLikeArtist && !$looksLikeAlbum) {
								main::INFOLOG && $log->is_info && $log->info(
									"Wikipedia skipping artist page '$page2->{title}' (looks like artist, not $type)"
								);
								_doFulltextSearch($class, $client, $cb, $type, $args, $lang, $localizedType);
								return;
							}

							main::INFOLOG && $log->is_info && $log->info(
								"Wikipedia direct title hit: '$page2->{title}' lang=$lang"
							);
							$class->getPage($client, sub {
								my $review = shift;

								# Проверяем: упоминается ли наш артист в тексте статьи?
								# Именно это не даёт статье про трансовый дуэт "Above & Beyond"
								# попасть вместо альбома Deep Purple "Above And Beyond".
								if ($review->{contentText} && $args->{artist}) {
									unless (_artistInText($review->{contentText}, $args->{artist})) {
										main::INFOLOG && $log->is_info && $log->info(
											"Wikipedia artist sanity check FAILED for '$page2->{title}': "
											. "'$args->{artist}' not found in article. Falling back to fulltext search."
										);
										_doFulltextSearch($class, $client, $cb, $type, $args, $lang, $localizedType);
										return;
									}
								}

								$review->{review}     = delete $review->{content};
								$review->{reviewText} = delete $review->{contentText};
								$cb->($review);
							}, { title => $page2->{title}, id => $page2->{pageid}, lang => $lang });
							return;
						}

						# fallback to fulltext search
						_doFulltextSearch(
							$class,
							$client,
							$cb,
							$type,
							$args,
							$lang,
							$localizedType
						);
					},

					{
						cache   => 1,
						expires => 86400,
					}
				);

				return;
			}

			# ----------------------------------------------------------
			# 3. FALLBACK:
			# fulltext search
			# ----------------------------------------------------------

			_doFulltextSearch(
				$class,
				$client,
				$cb,
				$type,
				$args,
				$lang,
				$localizedType
			);
		},

		{
			cache   => 1,
			expires => 86400,
		}
	);
}

sub _doFulltextSearch {
	my (
		$class,
		$client,
		$cb,
		$type,
		$args,
		$lang,
		$localizedType
	) = @_;

	Plugins::MusicArtistInfo::Common->call(

		sprintf(
			SEARCH_URL,
			$lang,

			uri_escape_utf8(
				'"'
				. $args->{title}
				. '" '
				. $localizedType
				. ' "'
				. $args->{artist}
				. '"'
			)
		),

		sub {
			my $searchResults = shift;
			my $candidates = eval('$searchResults->{query}->{search}') || [];
			$log->warn($@) if $@;

			my ($candidate) = sort { $b->{ranking} <=> $a->{ranking} }
			grep { $_->{ranking} > 5; }
			map {
				$_->{snippet} = _removeMarkup($_->{snippet});
				$_->{categorysnippet} = _removeMarkup($_->{categorysnippet});

				# Кэшируем нормализованные целевые строки из LMS
				my $normTargetTitle  = _normalizeName($args->{title});
				my $normTargetArtist = _normalizeName($args->{artist});

				# Берем заголовок статьи из Википедии и вычищаем из него суффиксы типа "(альбом)" или "(сингл)"
				my $title = $_->{title};
				$title =~ s/\s*\(.*(?:$type|$localizedType)\)//ig;
				
				# ПРИМЕНЯЕМ НАШУ НОРМАЛИЗАЦИЮ К ЗАГОЛОВКУ СТАТЬИ
				$title = _normalizeName($title);

				$_->{ranking} = 0;

				# 1. Полное совпадение нормализованных названий (очень надежно)
				if ( _rank( $_, $title eq $normTargetTitle, 10, 'exact title match' ) ) {}

				# 2. Частичное совпадение (одно название начинается с другого)
				elsif (
					_rank(
						$_,
						(index($title, $normTargetTitle) == 0 || index($normTargetTitle, $title) == 0),
						7,
						'partial title match'
					)
				) {}

				# 3. Levenshtein (на случай мелких опечаток/символов)
				elsif ( _rank( $_, Text::Levenshtein::distance($title, $normTargetTitle) < 10, 5, 'levenshtein 10' ) ) {}

				# Нормализуем сниппет статьи для поиска упоминания артиста
				my $normSnippet = _normalizeName($_->{snippet});

				# 4. Проверки артиста в тексте сниппета
				if ( _rank( $_, $normSnippet eq $normTargetArtist, 5, 'artist match' ) ) {}

				elsif ( _rank( $_, index($normSnippet, $normTargetArtist) == 0, 3, 'snippet starts with artist' ) ) {}

				elsif ( _rank( $_, index($normSnippet, $normTargetArtist) != -1, 2, 'snippet has artist' ) ) {}

				# 5. Сниппет содержит и название, и тип (альбом/сингл)
				_rank(
					$_,
					(index(lc($_->{snippet}), lc($args->{title})) != -1 && $_->{title} =~ /$type|$localizedType/i),
					1,
					"snippet has $type"
				);

				# Бонус за длинное имя
				_rank( $_, $title eq $normTargetTitle && length($normTargetTitle) > 20, 5, "matches a long $type title" );

				main::INFOLOG && $log->is_info && $log->info(Data::Dump::dump($_));

				$_;
			} @$candidates;

			main::INFOLOG
				&& $log->is_info
				&& $log->info(
					Data::Dump::dump(
						$candidate
						? $candidate
						: $candidates
					)
				);

			$candidate ||= {};

			# fallback to English
			if (
				!$candidate->{pageid}
				&& $lang ne 'en'
			) {

				$args->{lang} = 'en';

				return $class->getAlbumOrWorkReview(
					$client,
					$cb,
					$type,
					$args
				);
			}

			$class->getPage(

				$client,

				sub {
					my $review = shift;

					$review->{review}     = delete $review->{content};
					$review->{reviewText} = delete $review->{contentText};

					$cb->($review);
				},

				{
					title => $candidate->{title},
					id    => $candidate->{pageid},
					lang  => $args->{lang},
				}
			);
		},

		{
			cache   => 1,
			expires => 86400,
		}
	);
}

sub getBiography {
	my ( $class, $client, $cb, $args ) = @_;
	
	# Нормализация UTF-8 для безопасного сравнения кириллицы
	for my $k (qw(artist title album)) {
		next unless defined $args->{$k};
		if ( !Encode::is_utf8($args->{$k}) ) {
			$args->{$k} = Encode::decode_utf8($args->{$k}, Encode::FB_DEFAULT);
		}
	}
	
	my $useLang = validateLanguage($client, $args->{lang});
	main::INFOLOG && $log->is_info && $log->info("Wikipedia getBiography: artist='$args->{artist}' lang=$useLang");
	
	Plugins::MusicArtistInfo::Common->call(
		sprintf(SEARCH_URL, $useLang, uri_escape_utf8($args->{artist})),
		sub {
			my $searchResults = shift;

			my $candidates = eval('$searchResults->{query}->{search}') || [];

			$log->warn($@) if $@;

			my $artistLen = length($args->{artist});
			my $levThreshold = $artistLen <= 5 ? 2 : 5;

			my ($candidate) = sort {
				$b->{_score} <=> $a->{_score}
			} grep {
				$_->{_score} > 0
			} map {
				$_->{snippet} = _removeMarkup($_->{snippet});
				$_->{categorysnippet} = _removeMarkup($_->{categorysnippet});

				# --- ЖЕСТКАЯ ЗАЩИТА ОТ SELF-TITLED АЛЬБОМОВ В БИОГРАФИЯХ ---
				# Если мы ищем БИОГРАФИЮ, а в заголовке Википедии явно указан альбом/сингл/песня,
				# мы полностью игнорируем этого кандидата (возвращаем пустой хеш, score будет 0)
				if ($_->{title} =~ /\((?:альбом|сингл|песня|дискография|album|single|song|discography)\)/i) {
					main::INFOLOG && $log->is_info && $log->info("[Strict Filter] Полностью исключаем релиз из биографий: $_->{title}");
					$_->{_score} = -100;
					# Чтобы map не передавал его дальше с положительным балансом, сразу обнуляем очки
				} else {

					my $score = 0;
					my $isExact = 0;
					
					# --- УМНАЯ ПРОВЕРКА РУССКИХ ФИО ---
					my $normArtist = _normalizeName($args->{artist});
					my $normTitle  = _normalizeName($_->{title});

					my @parts = split(/\s+/, $normArtist);
					my $revArtist = join(' ', reverse @parts);

					# 1. Точное совпадение очищенных строк (Сергей Бабкин == сергей бабкин)
					if ($normTitle eq $normArtist || $normTitle eq $revArtist) {
						$score += 15;
						$isExact = 1;
					} 
					# 2. Начинается с артиста или инверсии
					elsif (index($normTitle, $normArtist) == 0 || index($normTitle, $revArtist) == 0) {
						$score += 10;
						$isExact = 1;
					} 
					# 3. Допущение опечаток
					elsif (Text::Levenshtein::distance($normTitle, $normArtist) <= $levThreshold ||
						   Text::Levenshtein::distance($normTitle, $revArtist) <= $levThreshold) {
						$score += 5;
					}
					
					# 4. Жесткий штраф за страницы значений (дизамбиги)
					if (
						$_->{title} =~ /\(значения\)/i || # <-- Бронебойная защита от мусора
						$_->{categorysnippet} =~ /страниц.*значени|disambiguation/i || 
						$_->{snippet} =~ /может означать|может относиться/i ||
						$_->{snippet} =~ /^<span class="searchmatch">.*?<\/span>.*?:\s*<span/ ||
						( () = $_->{snippet} =~ /\(род\./g ) >= 2
					) {
						$score = -100;
						main::INFOLOG && $log->is_info && $log->info("Влепили штраф дизамбигу: $_->{title}");
					} 
					
					# 5. Sanity check: исправили баг приоритета операторов (!$_->{categorysnippet} !~ ...)
					# Теперь проверяем чистое регулярное выражение к строке категории
					if (!$isExact && ($_->{categorysnippet} // '') !~ /музыкант|певц|певе|групп|band|musician|singer|group/i) {
						unless (_artistInText($_->{title}, $args->{artist}) || _artistInText($_->{snippet}, $args->{artist})) {
							$score = 0;
						}
					}

					# 6. Бонусы за профессию
					if ($score > 0) {
						if (
							$_->{categorysnippet} =~ /музыкант|музыкальн|band|musician|singer|рок|певц|певе[цч]|певиц|дискограф|альбом|исполнител|солист|групп/i || 
							$_->{snippet} =~ /музыкальн|band|group|альбом|дискограф|певц|певе[цч]|солист|рок|групп/i
						) {
							$score += 8;
						}
					}

					$_->{_score} = $score;
				}
				$_;
			} @$candidates;
			
			main::INFOLOG && $log->is_info && $log->info(Data::Dump::dump($candidate ? $candidate : $candidates));

			$candidate ||= {};

			if (!$candidate->{pageid} && validateLanguage($client, $args->{lang}) ne 'en') {
				$args->{lang} = 'en';
				return $class->getBiography($client, $cb, $args);
			}

			$class->getPage($client, sub {
				my $bio = shift;

				$bio->{bio} = delete $bio->{content};
				$bio->{bioText} = delete $bio->{contentText};

				$cb->($bio);
			}, {
				title => $candidate->{title},
				id => $candidate->{pageid},
				lang => $args->{lang},
			});
		},{
			cache => 1,
			expires => 86400,	# force caching - wikipedia doesn't want to cache by default
		}
	);
}
##Добавлен хелпер _artistInText (перед _removeMarkup). Он делает два уровня проверки:

#Полное имя артиста — index(lc($text), lc($artist)). Для "Deep Purple" это сработает напрямую.
#Для многословных имён — все слова длиннее 3 символов должны встречаться в тексте. Это обрабатывает варианты написания, но не даёт ложных срабатываний на короткие слова типа "The", "And".
sub _artistInText {
	my ($text, $artist) = @_;

	return 0 unless $text && $artist;

	# Прямая проверка полного имени (без учёта регистра)
	return 1 if index(lc($text), lc($artist)) != -1;

	# Для многословных имён (например "Deep Purple"):
	# все слова длиннее 3 символов должны встречаться в тексте.
	# Короткие слова ("The", "And") игнорируем — они дают ложные срабатывания.
	my @words = grep { length($_) > 3 } split(/\s+/, $artist);
	if (@words >= 1) {
		my $matched = grep { index(lc($text), lc($_)) != -1 } @words;
		return 1 if $matched == scalar @words;
	}
	return 0;
}

sub _removeMarkup {
	HTML::FormatText->format_string(
		$_[0],
		leftmargin => 0,
	);
}

sub _normalizeName {
	my $s = shift || '';
	$s = lc($s);
	# Убираем запятые, точки, скобки
	$s =~ s/[,.\(\)]/ /g;
	# Схлопываем множественные пробелы в один
	$s =~ s/\s+/ /g;
	# Убираем пробелы по краям
	$s =~ s/^\s+|\s+$//g;
	return $s;
}

sub getPage {
	my ( $class, $client, $cb, $args ) = @_;

	if (!$args->{id}) {
		return $cb->({
			error => cstring($client, 'PLUGIN_MUSICARTISTINFO_NOT_FOUND')
		});
	}
	my $lang = validateLanguage($client, $args->{lang});
	main::INFOLOG && $log->is_info && $log->info("Wikipedia getPage: id=$args->{id} lang=$lang title=" . ($args->{title} || '?'));	
	Plugins::MusicArtistInfo::Common->call(
		sprintf(FETCH_URL, $lang, uri_escape_utf8($args->{id})),
		sub {
			my $fetchResults = shift;

			my $result = {};

			if ( $fetchResults && ref $fetchResults && $fetchResults->{query} && (my $content = $fetchResults->{query}->{pages}) ) {
				if (length($content->[0]->{extract}) > MIN_REVIEW_SIZE) {
					$result->{content} = $content->[0]->{extract};

					# sometimes we'd receive partial content which had been stripped out by the wikipedia API - let's remove from there on
					my $deadEndFound;
					$result->{content} = join('', grep {
						$deadEndFound ||= $_ =~ /data-mw-anchor=\\?"(?:Track_listing|Notes|Scores|Locations|Technical|Charts|References|Discography|Filmography|See_also|Explanatory_footnotes|Further_reading|Accolades|Einzelnachweise|Musikbeispiele|Auszeichnungen|Diskografie|Werbetestimonial|Filmmusik)/i;
						!$deadEndFound;
					} split(/\n/, $result->{content}));

					$result->{contentText} = _removeMarkup($result->{content});
					$result->{content} = '<link rel="stylesheet" type="text/css" href="/plugins/MusicArtistInfo/html/mai.css" />'
						. $result->{content}
						. '<div>(' . cstring($client, 'SOURCE') . cstring($client, 'COLON') . ' Wikipedia)</div>';

					my $slug = $args->{title};
					$slug =~ s/ /_/g;
					$result->{url} = sprintf(PAGE_URL, validateLanguage($client, $args->{lang}), uri_escape_utf8($slug));
				}
			}

			if ( !$result->{content} && !main::SCANNER ) {
				$result->{error} ||= cstring($client, 'PLUGIN_MUSICARTISTINFO_NOT_FOUND');
			}

			$cb->($result);
		},{
			cache => 1,
			expires => 86400,	# force caching - wikipedia doesn't want to cache by default
		}
	);
}

1;
