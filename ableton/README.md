# Ableton side: AbletonOSC + StageDeck extension

This folder contains a copy of [AbletonOSC](https://github.com/ideoforms/AbletonOSC)
(MIT licence, by Daniel John Jones and contributors, commit `0ca6821`) plus one extra handler,
`abletonosc/master.py`, that exposes the master track, cue volume and return tracks, which
upstream does not: master volume / pan / cue / meter, return volume / mute / pan / sends, and the
devices (with parameters, set and listen) on the master and on each return, so the mixer can show
a filter on a group, a return or the master. It is registered in `manager.py` and `abletonosc/__init__.py`
(look for the "StageDeck extension" comments).

## Install (2 minutes)

1. Copy the whole `AbletonOSC` folder to your Remote Scripts folder:
   * macOS: `~/Music/Ableton/User Library/Remote Scripts/AbletonOSC`
   * Windows: `\Users\<you>\Documents\Ableton\User Library\Remote Scripts\AbletonOSC`
2. Restart Live (11 or 12).
3. Preferences → Link/Tempo/MIDI → Control Surface: pick **AbletonOSC** (input/output: none).
4. Live shows "AbletonOSC: Listening for OSC on port 11000" in the status bar.

AbletonOSC listens on UDP 11000 and answers on UDP 11001 to the IP that sent the request.
StageDeck finds Live automatically (UDP broadcast of `/live/test`) when both devices are on the
same network, or you type the Mac's IP in Settings.

## Log file

`Remote Scripts/AbletonOSC/logs/abletonosc.log` – useful if something does not respond.
