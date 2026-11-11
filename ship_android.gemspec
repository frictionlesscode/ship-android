Gem::Specification.new do |s|
  s.name = "ship_android"
  s.version = "1.0.0"
  s.summary = "Shared fastlane lanes for shipping frictionlesscode's Android apps to Google Play"
  s.authors = ["Michael Swanson"]
  s.license = "MIT"
  s.files = Dir["lib/**/*"]
  s.required_ruby_version = ">= 3.1"
  # fastlane is the app's dependency, not ours: the lanes run inside the app's fastlane.
end
