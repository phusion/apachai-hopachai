function __cleanup()
{
	set +e

	# Kill all child processes.
	local pids=`jobs -p`
	if [[ "$pids" != "" ]]; then
		kill $pids
	fi

	# Run user-defined cleanup function.
	if [[ "`type cleanup 2>/dev/null`" =~ function ]]; then
		cleanup
	fi
}

trap __cleanup EXIT
