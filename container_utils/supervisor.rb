# An init process for inside the container, which reaps
# all adopted children.

main_child = fork do
	exec(*ARGV)
end

while true
	pid = Process.waitpid(-1)
	if pid == main_child
		exit($?.exitstatus)
	end
end
