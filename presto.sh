#!/usr/bin/env sh
# Presto is a gapless, randomizing, classical music player written in POSIX shell
#
# This script is a stripped down version of 'Giocoso' (https://absolutelybaching.com/what-is-giocoso).
# I just rewrote it in POSIX shell and removed some features I didn't need.
# All credit goes to Howard Rogers for the original script.
# Giocoso v2.00 (22nd July 2022) was the one used as the base script.
#
# Copyright © Columndeeply 2023
# Copyright © Howard Rogers 2021,2022
#
# Version: 1.0.1 - 2023/02/11
#
# This program is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# version 2.0 only of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# A full copy of the GNU General Public License can be found here:
# https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#

# Colors
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
MAGENTA="$(tput setaf 5)"
NORMAL="$(tput setaf 7)"

# Set some variables
CONF_DIR="$HOME/.config/presto"
LIB_DIR="$HOME/Server/audio/music/classical/flac"
DB_FILE="$CONF_DIR/database.db"
PLAYLIST_FILE="$CONF_DIR/playlist"
FILES_REFRESH="/tmp/all_files_presto"
FOLDERS_REFRESH="/tmp/all_folders_presto"
CSV_REFRESH="/tmp/csv_import_presto"

# Default filters
MAX_PLAYS=9999
NO_FILTERS=0
HOURS_LIMIT=5
NEVER_PLAYED=0
MAX_LENGTH_STR="1=1"
FILTER_COMPOSER_STR="1=1"
FILTER_COMPOSITION_STR="1=1"
FILTER_GENRE_STR="1=1"
FILTER_CONDUCTOR_STR="1=1"
FILTER_PERFORMER_STR="1=1"

# Create the config directory and database (if missing)
[ ! -d "$CONF_DIR" ] && mkdir -p "$CONF_DIR"
[ ! -e "$DB_FILE" ] && touch "$DB_FILE"
[ ! -e "$PLAYLIST_FILE" ] && touch "$PLAYLIST_FILE"

# Misc
help() {
	echo "  Presto is a gapless randomizing classical music player written in POSIX shell."
	echo ""
	echo "  Options:"
	echo "    --help | -h: show this message."
	echo "    --refresh | -r: scans the library for new files."
	echo ""
	echo "  Filters:"
	echo "    --all: disables all filters. This means it'll pick a composition at random from the library."
	echo "    --no-limit: disables the 'recently played' filter. This means it'll play anything even if it is by a composer that has been played in the previous $HOURS_LIMIT hours."
	echo "    --never-played: it'll only play compositions that have never been played before."
	echo "    --max-plays={X}: it'll only play {X} compositions."
	echo "    --max-length={X}: it'll only play compositions with a length of less than {X} minutes."
	echo ""
	echo "  Metadata filters:"
	echo "  All of these filters are case insensitive and will return partial matches. Searching for composer=alex will return compositions by 'Alexander Borodin', 'Alexander Scriabin', etc."
	echo "    --composer={X}"
	echo "    --composition={X}"
	echo "    --genre={X}"
	echo "    --conductor={X}"
	echo "    --performer={X}"
}

notify_and_exit() {
	echo "$1"
	exit
}

play_time() {
	LENGTH=0
	LENGTH_STR=0
	for f in *.flac; do
		FILE_LENGTH="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"
		LENGTH_STR="$LENGTH_STR+$FILE_LENGTH"
	done

	LENGTH="$(echo "$LENGTH_STR" | bc )"
	LENGTH_SEC="$(echo "$LENGTH" | awk '{print int($1)}')"
	PLAY_LENGTH="$(convert_secs "$LENGTH_SEC")"
	CONCLUDE="$(date --date="+$LENGTH_SEC seconds" "+%T")"
}

convert_secs() {
	h="$(( $1 / 3600 ))"
	m="$(( ($1 % 3600 ) / 60 ))"
	s="$(( $1 % 60 ))"

	printf "%02.f:%02.f:%02.f" $h $m $s
}

count_flacs() {
	COUNT="$(find . -type f -name '*.flac' | wc -l)"
	[ -z "$COUNT" ] || [ "$COUNT" -eq 0 ] && notify_and_exit "   No flac files in current folder. Exiting..."
}

# Display function
display() {
	clear
	echo ""
	echo "  Currently playing:$MAGENTA $DISPLAY_ALBUM $NORMAL"
	echo "    Composed by$GREEN $DISPLAY_COMPOSER $NORMAL"
	echo "    Performed by$GREEN $DISPLAY_PERFORMER $NORMAL"
	[ -n "$DISPLAY_CONDUCTOR" ] && echo "    Conducted by$GREEN $DISPLAY_CONDUCTOR $NORMAL"
	echo "    Length:$GREEN $PLAY_LENGTH $NORMAL"
	echo ""
	if [ -n "$FILTERS" ]; then
		printf "  Applied filters:"
		echo "$FILTERS"
		echo ""
	fi
	echo "  Playback will finish at$MAGENTA $CONCLUDE $NORMAL"
	echo ""
	printf "  Press Ctrl+C to quit "
}

# Database functions
create_database() {
	# Check if the database is empty, if it is create all the tables
	if [ ! -s "$DB_FILE" ]; then
		sqlite3 "$DB_FILE" \
			"
			CREATE TABLE tracks (
			  path TEXT,
			  composer TEXT,
			  composition TEXT, 
			  genre TEXT,
			  conductor TEXT,
			  performer TEXT, 
			  tracknumber TEXT,
			  title TEXT,
			  duration NUMERIC
			);
			CREATE TABLE compositions (
			  id INTEGER NOT NULL, 
			  path TEXT, 
			  composer TEXT, 
			  composition TEXT, 
			  genre TEXT, 
			  conductor TEXT, 
			  performer TEXT, 
			  duration NUMERIC, 
			  PRIMARY KEY (id AUTOINCREMENT)
			);
			CREATE TABLE history (
			  id INTEGER NOT NULL, 
			  date_play TEXT, 
			  path TEXT, 
			  composer TEXT, 
			  composition TEXT, 
			  genre TEXT, 
			  conductor TEXT,
			  performer TEXT, 
			  duration NUMERIC, 
			  PRIMARY KEY (id AUTOINCREMENT)
			);

			CREATE INDEX IF NOT EXISTS path_plays ON history (path);
			CREATE INDEX IF NOT EXISTS path_composer ON compositions (composer, path);
			CREATE INDEX IF NOT EXISTS path_genre ON compositions (genre, path);
			CREATE INDEX IF NOT EXISTS path_conductor ON compositions (conductor, path);
			CREATE INDEX IF NOT EXISTS path_performer ON compositions (performer, path);
			CREATE INDEX IF NOT EXISTS path_duration ON compositions (duration, path);
			CREATE INDEX IF NOT EXISTS path_composition ON compositions (composition, path);
			"
	fi
}

refresh_database() {
	clear
	echo ""
	echo "  Scanning $LIB_DIR"
	echo ""

	# Remove anything left from previous runs
	rm -f "$FILES_REFRESH" "$FILES_REFRESH-2" "$FOLDERS_REFRESH" "$CSV_REFRESH"

	# Get all flac files
	find "$LIB_DIR" -type f -name "*.flac" 2>/dev/null >> "$FILES_REFRESH"

	# If nothing found, exit
	[ "$(wc -l < "$FILES_REFRESH")" -eq 0 ] && notify_and_exit "  There are no FLAC files in $LIB_DIR. Exiting..."

	while read -r line; do
		dirname "$line" >> "$FILES_REFRESH-2"
	done < "$FILES_REFRESH"

	sort "$FILES_REFRESH-2" | uniq > "$FOLDERS_REFRESH"

	# Process all the files
	while read -r folder; do
		echo "  Adding $(basename "$folder")"
		for f in "$folder"/*.flac; do
			COMPOSER="$(metaflac --show-tag=COMPOSER "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			ALBUM="$(metaflac --show-tag=ALBUM "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			GENRE="$(metaflac --show-tag=GENRE "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			CONDUCTOR="$(metaflac --show-tag=CONDUCTOR "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			PERFORMER="$(metaflac --show-tag=PERFORMER "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			TRACKNUMBER="$(metaflac --show-tag=TRACKNUMBER "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			TITLE="$(metaflac --show-tag=TITLE "$f" | sed 's/.*=//g' | sed 's/\"/\\\"/g')"
			DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null)"

			echo "$folder|$COMPOSER|$ALBUM|$GENRE|$CONDUCTOR|$PERFORMER|$TRACKNUMBER|$TITLE|$DURATION" >> "$CSV_REFRESH"
		done
	done < "$FOLDERS_REFRESH"

	# Empty out database
	sqlite3 "$DB_FILE" "DELETE FROM tracks; DELETE FROM compositions; DELETE FROM sqlite_sequence WHERE name='compositions'" >/dev/null

	# Import the CSV
	printf ".separator |\\n.import %s tracks" "$CSV_REFRESH" | sqlite3 "$DB_FILE"

	# Fill the other tables
	sqlite3 "$DB_FILE" "INSERT INTO compositions SELECT DISTINCT null, path, composer, composition, genre, conductor, performer, null FROM tracks"
	sqlite3 "$DB_FILE" "WITH ad AS (SELECT composer, path, SUM(duration) AS duration FROM tracks GROUP BY composer, path) UPDATE compositions AS c SET duration=(SELECT duration FROM ad WHERE ad.composer=c.composer AND ad.path=c.path)"

	# Rebuild indexes
	sqlite3 "$DB_FILE" "REINDEX compositions"
	sqlite3 "$DB_FILE" "REINDEX history"

	notify_and_exit "  Your library has been scanned successfully"
}

record_play() {
	RECORD_COMPOSER=$(echo "$DISPLAY_COMPOSER" | sed "s/'/''/g")
	RECORD_ALBUM=$(echo "$DISPLAY_ALBUM" | sed "s/'/''/g")
	RECORD_CONDUCTOR=$(echo "$DISPLAY_CONDUCTOR" | sed "s/'/''/g")
	RECORD_PERFORMER=$(echo "$DISPLAY_PERFORMER" | sed "s/'/''/g")
	RECORD_GENRE="$(metaflac --show-tag=GENRE "$1" | sed 's/.*=//g')"
	RECORD_PATH=$(echo "$2" | sed "s/'/''/g")

	sqlite3 "$DB_FILE" "INSERT INTO history VALUES (null, datetime('now', 'localtime'), '$RECORD_PATH', '$RECORD_COMPOSER', '$RECORD_ALBUM', '$RECORD_GENRE', '$RECORD_CONDUCTOR', '$RECORD_PERFORMER', '$LENGTH')"
}

# Check parameters
check_params() {
	TMP_FILTERS="\n    $BLUE ...by a composer not played in the last $HOURS_LIMIT hours$NORMAL"

	# Check if some specific parameters have been given before checking anything else
	# --all: disregard all other parameters, we want to shuffle the whole library
	for param in "$@"; do
		if [ "$param" = "--all" ]; then
			FILTERS="    $BLUE all filters have been disabled$NORMAL"
			NO_FILTERS=1

			return
		fi
	done

	for param in "$@"; do
		case "$param" in
			"--help"|"-h") help; exit ;;
			"--refresh"|"-r") refresh_database ;;

			# Search filters
			"--no-limit") # Allow picking stuff that has been played recently
				FILTERS="$FILTERS\n    $BLUE ...no recently played limit$NORMAL"

				TMP_FILTERS=""
				HOURS_LIMIT=0
				;;
			"--never-played") # Only play compositions not found in the history tab
				FILTERS="$FILTERS\n    $BLUE ...only compositions never played before$NORMAL"

				NEVER_PLAYED=1
				;;
			"--max-plays"*) # Only play X compositions
				MAX_PLAYS="$(echo "$param" | sed 's/.*=//g')"

				FILTERS="$FILTERS\n    $BLUE ...only play $MAX_PLAYS compositions$NORMAL"
				;;
			"--max-length"*) # Only allow stuff with shorter a duration
				MAX_LENGTH="$(echo "$param" | sed 's/.*=//g')"
				MAX_LENGTH_STR="(duration/60) < $MAX_LENGTH"

				FILTERS="$FILTERS\n    $BLUE ...maximum length of $MAX_LENGTH minutes$NORMAL"
				;;
			"--composer"*)
				FILTER_COMPOSER="$(echo "$param" | sed 's/.*=//g' | sed 's/ /\% \%/g')"
				FILTER_COMPOSER_STR="composer LIKE '%$FILTER_COMPOSER%'"

				FILTERS="$FILTERS\n    $BLUE ...with composer-specific search for: $FILTER_COMPOSER $NORMAL"
				;;
			"--composition"*)
				FILTER_COMPOSITION="$(echo "$param" | sed 's/.*=//g' | sed 's/ /\% \%/g')"
				FILTER_COMPOSITION_STR="composition LIKE '%$FILTER_COMPOSITION%'"

				FILTERS="$FILTERS\n    $BLUE ...with composition-specific search for: $FILTER_COMPOSITION $NORMAL"
				;;
			"--genre"*)
				FILTER_GENRE="$(echo "$param" | sed 's/.*=//g' | sed 's/ /\% \%/g')"
				FILTER_GENRE_STR="genre LIKE '%$FILTER_GENRE%'"

				FILTERS="$FILTERS\n    $BLUE ...with genre-specific search for: $FILTER_GENRE $NORMAL"
				;;
			"--conductor"*)
				FILTER_CONDUCTOR="$(echo "$param" | sed 's/.*=//g' | sed 's/ /\% \%/g')"
				FILTER_CONDUCTOR_STR="conductor LIKE '%$FILTER_CONDUCTOR%'"

				FILTERS="$FILTERS\n    $BLUE ...with conductor-specific search for: $FILTER_CONDUCTOR $NORMAL"
				;;
			"--performer"*)
				FILTER_PERFORMER="$(echo "$param" | sed 's/.*=//g' | sed 's/ /\% \%/g')"
				FILTER_PERFORMER_STR="performer LIKE '%$FILTER_PERFORMER%'"

				FILTERS="$FILTERS\n    $BLUE ...with performer-specific search for: $FILTER_PERFORMER $NORMAL"
				;;
		esac
	done

	[ -z "$TMP_FILTERS" ] || FILTERS="$TMP_FILTERS$FILTERS"
}

# Search function
search_music() {
	COUNT="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM compositions")"
	[ "$COUNT" -eq 0 ] && notify_and_exit "  No files found in your library. Please use --refresh to scan it. Exiting..."

	if [ "$NO_FILTERS" = "1" ]; then
		ALBUM_SQL="SELECT path FROM compositions ORDER BY RANDOM() LIMIT 1"
		ALBUM="$(sqlite3 "$DB_FILE" "$ALBUM_SQL")"
	else
		# Default query
		ALBUM_SQL="SELECT path FROM compositions WHERE $FILTER_COMPOSER_STR AND $FILTER_COMPOSITION_STR AND $FILTER_GENRE_STR AND $FILTER_CONDUCTOR_STR AND $FILTER_PERFORMER_STR AND $MAX_LENGTH_STR"

		# If there's an hourly limit add to the query
		if [ "$HOURS_LIMIT" -gt 0 ]; then
			# Composer specific
			ALBUM_SQL="$ALBUM_SQL AND composer NOT IN (SELECT composer FROM history WHERE date_play > datetime('now', 'localtime', '-$HOURS_LIMIT hours'))"
		fi

		# Only compositions never played before
		if [ "$NEVER_PLAYED" -gt 0 ]; then
			ALBUM_SQL="$ALBUM_SQL AND composer||composition||conductor||performer||duration NOT IN (SELECT composer||composition||conductor||performer||duration FROM history)"
		fi

		# Pick one at random
		ALBUM_SQL="$ALBUM_SQL ORDER BY RANDOM() LIMIT 1"

		ALBUM="$(sqlite3 "$DB_FILE" "$ALBUM_SQL")"
	fi
}

# The real music player
play() {
	rm -f "$PLAYLIST_FILE"

	first_file="$(find "$(pwd)" -type f -name '*.flac' | sort | head -n 1)"

	# Get metadata
	DISPLAY_ALBUM="$(metaflac --show-tag=ALBUM "$first_file" | sed 's/.*=//g')"
	DISPLAY_COMPOSER="$(metaflac --show-tag=COMPOSER "$first_file" | sed 's/.*=//g')"
	DISPLAY_CONDUCTOR="$(metaflac --show-tag=CONDUCTOR "$first_file" | sed 's/.*=//g')"
	DISPLAY_PERFORMER="$(metaflac --show-tag=PERFORMER "$first_file" | sed 's/.*=//g')"

	for f in *.flac; do
		filename="$(basename "$f")"
		albumdir="$(dirname "$(pwd)/$f")"

		full_path="$(pwd)/$filename"
		echo "file '$(echo "$full_path" | sed "s/'/\'\\\'\'/g")'" >> "$PLAYLIST_FILE"
	done

	# Display the playing screen
	display

	# Do the actual playing
	ffmpeg -nostdin -hide_banner -loglevel 0 -f concat -safe 0 -i "$PLAYLIST_FILE" -max_muxing_queue_size 900000 -f alsa "default"

	# Save it to history
	record_play "$first_file" "$albumdir"
}

# Run the program
create_database
check_params "$@"

plays=0
while true; do
	search_music
	[ -z "$ALBUM" ] && notify_and_exit "  Nothing found with current filters. Exiting..."

	cd "$ALBUM" > /dev/null 2>&1 || exit
	count_flacs

	play_time
	play

	plays="$(( plays + 1 ))"
	[ "$plays" -eq "$MAX_PLAYS" ] && exit

	sleep 15
done
