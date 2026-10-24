require "bundler/setup"
require "zlib"
require "stringio"
require_relative "../lib/fizzy_pop"

def check(condition, message)
  raise message unless condition
end

def minimum_version(actual, minimum, name)
  check(Gem::Version.new(actual) >= Gem::Version.new(minimum), "#{name}: #{actual} < #{minimum}")
  puts "#{name}=#{actual}"
end

minimum_version(RUBY_VERSION, "3.4.12", "Ruby")
minimum_version(JSON::VERSION, "2.19.2", "JSON")
minimum_version(Zlib::VERSION, "3.2.3", "zlib")
default_zlib = Gem::Specification.find_all_by_name("zlib").find(&:default_gem?)
check(default_zlib, "Missing default zlib gem")
minimum_version(default_zlib.version.to_s, "3.2.3", "default zlib")

# These gems belong to the development/deployment bundle, not the service bundle.
lock = Bundler::LockfileParser.new(Bundler.read_file(Bundler.default_lockfile))
{ "concurrent-ruby" => "1.3.7", "activesupport" => "8.1.2.1", "uri" => "1.1.2" }.each do |name, minimum|
  minimum_version(lock.specs.find { |spec| spec.name == name }.version.to_s, minimum, "locked #{name}")
end
if ENV["BUNDLE_WITHOUT"].to_s.split(":").include?("development")
  check(!Gem.loaded_specs.key?("kamal"), "Kamal must not load in the runtime bundle")
  check(!Gem.loaded_specs.key?("concurrent-ruby"), "concurrent-ruby must not load in the runtime bundle")
end

# Exercise JSON with the option from the advisory, using harmless duplicate keys.
begin
  JSON.parse('{"%s%s":1,"%s%s":2}', allow_duplicate_key: false)
  raise "Duplicate JSON keys were accepted"
rescue JSON::ParserError
  puts "Duplicate JSON keys rejected"
end

message = "Notification: café ☕\nquoted: \"hello\""
openclaw = FizzyPop::WebhookAdapters.build("openclaw")
check(JSON.parse(openclaw.payload("test-agent", message)) == {
  "agentId" => "test-agent", "message" => message, "mode" => "now", "deliver" => false
}, "OpenClaw JSON payload changed")
hermes = FizzyPop::WebhookAdapters.build("hermes", route: "/webhooks/test")
payload = hermes.payload("test-agent", message)
check(JSON.parse(payload) == {
  "event_type" => "fizzy_notification", "agent" => "test-agent", "message" => message
}, "Hermes JSON payload changed")
check(hermes.url("http://example.invalid") == "http://example.invalid/webhooks/test", "Hermes route changed")
signature = hermes.headers("test-only-secret", payload).fetch("x-webhook-signature")
check(signature == OpenSSL::HMAC.hexdigest("SHA256", "test-only-secret", payload), "Hermes signature changed")

compressed = StringIO.new
writer = Zlib::GzipWriter.new(compressed)
writer.write(message)
writer.close
reader = Zlib::GzipReader.new(StringIO.new(compressed.string))
check(reader.read == message.b, "Gzip round trip failed")
reader.close

config = FizzyPop::Config.new(["--url", "http://example.invalid", "--token", "test-only", "--dry-run"])
check(config.dry_run && config.agents.first[:name] == "default", "CLI configuration changed")
puts "Security and application smoke checks passed (no network requests)"
