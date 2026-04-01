# lock that bundler
if (version = Gem::Version.new(Bundler::VERSION)) < Gem::Version.new('2.5.22')
  abort "Bundler version >= 2.5.22 is required. You are running #{version}"
end

source 'https://rubygems.org'
ruby '3.4.9'

# gem 'cocoapods', '~> 1.16.2'
gem 'bundler', '~> 2.6.9'
gem 'irb'

gem 'pry'
gem 'pry-stack_explorer'                             # enables the user to navigate the call-stack
gem 'pry-rescue'                                      # implementation of "break on unhandled exception" for Ruby
gem 'coderay'                             # a Ruby library for syntax highlighting.
# gem 'syntax_suggest'

# makes it easy and painless to work with XML and HTML from Ruby
# had to use the following to get to build on Mac if using homebrew
# bundle config build.nokogiri --use-system-libraries --with-xml2-include=/usr/include/libxml2/
gem 'nokogiri', '~> 1.19.0'

gem 'fastlane', '~> 2.232.2'
# gem 'fastlane', :github => 'fastlane/fastlane', :ref => 'd2d51a9af37f9b04a157e78fd25d147cecc89980'

gem 'rubyzip', '~> 2.4.1'
gem 'zip-zip'

# gem 'axlsx'
gem 'lexeme'

gem "dotenv"
gem "xcpretty"

# gem "google-cloud-translate-v3"
# gem "google-cloud-translate"

gem "abbrev"

gem 'stringio', '~> 3.1.7'

# gem 'psych', '~> 5.3.1'

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval(File.read(plugins_path), binding) if File.exist?(plugins_path)

