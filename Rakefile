desc "Build the application container"
task :app_container do
	sh "docker build --rm -t phusion/apachai-hopachai app"
end

desc "Build the sandbox"
task :sandbox do
	sh "docker build --rm -t phusion/apachai-hopachai-sandbox sandbox"
end
