# -*- encoding: utf-8 -*-

require 'rake'

Gem::Specification.new do |s|
  s.name = %q{file_overwrite}
  s.version = "0.1"
  # s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  # s.bindir = 'bin'
  s.authors = ["Masa Sakano"]
  s.date = Time.now.strftime("%Y-%m-%d")
  s.summary = %q{Class to overwrite an existing file safely}
  s.description = %q{This class provides a Ruby-oriented scheme to safely overwrite an existing file, leaving a backup file unless specified otherwise.  It writes a temporary file first, which is renamed to the original file in one action.  It accepts a block like some IO class-methods (e.g., each_line) and chaining like String methods (e.g., sub and gsub).}
  # s.email = %q{abc@example.com}
  s.extra_rdoc_files = [
    # "LICENSE",
     "README.en.rdoc",
  ]
  s.license = 'MIT'
  s.files = FileList['.gitignore','lib/**/*.rb','[A-Z]*','test/**/*.rb', '*.gemspec'].to_a.delete_if{ |f|
    ret = false
    arignore = IO.readlines('.gitignore')
    arignore.map{|i| i.chomp}.each do |suffix|
      if File.fnmatch(suffix, File.basename(f))
        ret = true
        break
      end
    end
    ret
  }
  s.files.reject! { |fn| File.symlink? fn }
  # s.add_runtime_dependency 'rails'
  # s.add_development_dependency "bourne", [">= 0"]
  s.homepage = %q{https://www.wisebabel.com}
  s.rdoc_options = ["--charset=UTF-8"]

  # s.require_paths = ["lib"]	# Default "lib"
  s.required_ruby_version = '>= 2.0'
  s.test_files = Dir['test/**/*.rb']
  s.test_files.reject! { |fn| File.symlink? fn }
  # s.requirements << 'libmagick, v6.0' # Simply, info to users.
  # s.rubygems_version = %q{1.3.5}      # This is always set automatically!!
end

