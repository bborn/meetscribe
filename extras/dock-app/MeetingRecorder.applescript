-- MeetingRecorder.applescript
-- A click-to-toggle Dock app for meetscribe.
-- Build:  ./scripts/install-launchers.sh   (or, by hand:)
--   osacompile -o ~/Applications/"Meeting Recorder.app" MeetingRecorder.applescript
-- Then drag the resulting app from ~/Applications to your Dock.

on run
	set meetscribe to "$HOME/.local/bin/meetscribe"
	set s to do shell script meetscribe & " status"
	if s starts with "RECORDING" then
		display notification "Saving transcript & audio…" with title "MeetScribe" subtitle "Stopping"
		do shell script meetscribe & " stop > /dev/null 2>&1 &"
	else
		do shell script meetscribe & " start > /dev/null 2>&1"
	end if
end run
