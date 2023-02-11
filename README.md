<p align="center">
  <img src="https://user-images.githubusercontent.com/106948293/218246788-3a354b31-be31-4692-8c9f-b56b25d5d857.png" />
</p>

# About _presto_
_presto_ is a gapless, trackless, randomizing, FLAC-only, classical music player written in POSIX shell.
It uses `ffmpeg` to play a full composition without pauses between tracks, and, by design, it can't be paused in the middle of playback.
A symphony should be heard as that, a symphony, not four smaller movements that you can pick and choose which ones you want to hear.

By default, it will play a composition at random from a composer that hasn't been played in the previous five hours but it can easily be filtered to pick only specific genres, composers, conductors, etc.
This way it avoids overplaying certain composers with a more extensive body of work than others.
Once a composer has been played it won't show up again in the next five hours.

# Requirements
_presto_ only needs four things: a POSIX compliant shell, `ffmpeg`, `flac` and `sqlite3`. Make sure to have them installed and you should be good to go. 

# Installation
    wget https://raw.githubusercontent.com/columndeeply/presto/main/presto.sh -O $HOME/.local/bin/presto
    chmod +x $HOME/.local/bin/presto

# Usage
## Parameters
_presto_'s randomizer can be modified using parameters. This can be used to filter works by some of its metadata.
All filters are case-insensitive and return partial matches. Using `--composer=alex` will return compositions by _Alexander Borodin_, _Alexander Scriabin_, _Boris Alexandrovich Chaykovsky_, etc. 
You can combine filters as you wish. The only one that overwrites everything else is `--all`. If you use that one, any other parameter will be ignored.

    Misc:
      --help | -h: show this message.
      --refresh | -r: scans the library for new files.

    Filters:
      --all: disables all filters. This means it'll pick a composition at random from the library.
      --no-limit: disables the 'recently played' filter.
      --never-played: it'll only play compositions that have never been played before.
      --max-plays={X}: it'll only play {X} compositions.
      --max-length={X}: it'll only play compositions with a length of less than {X} minutes.

    Metadata filters:
      --composer={X}
      --composition={X}
      --genre={X}
      --conductor={X}
      --performer={X}

## Library tags
_presto_ expects certain metadata tags in the library files. It might still work if some of the required tags are missing (or it might not, try it at your own risk).
Here are all the tags it tries to read when running a scan.

    COMPOSER: name of the composer (required)
    ALBUM: composition title (required)
    GENRE: genre of the composition (optional)
    CONDUCTOR: name of the conductor (optional)
    PERFORMER: list of performers (optional)
    TRACKNUMBER: track number (required)
    TITLE: track title (optional)

# License
Distributed under the GNU General Public License v2.0 licence. See the [LICENCE](https://github.com/columndeeply/presto/blob/main/LICENSE) file for more information.

# Acknowledgments
_presto_ is a stripped down version of _giocoso_ which is written and mantained by Howard Rogers (https://absolutelybaching.com/what-is-giocoso).
Many thanks to him for making such awesome software available under GPL.
If you're looking for features like displaying album covers or being able to pause in the middle of a composition, go check out _giocoso_.
