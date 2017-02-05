task :run do 
  sh "dub run --build=release"
end
task :default => [:run]
