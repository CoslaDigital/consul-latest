# frozen_string_literal: true

require Rails.root.join("lib/sensemaker_ext/loader")

def sensemaker_ext_python_ready?
  python_present = system("which python3 > /dev/null 2>&1")
  cli = Rails.root.join("vendor/sensemaking-tools/venv/bin/sensemaking-categorize")
  cli_present = File.file?(cli) && File.executable?(cli)

  return true if python_present && cli_present

  Rails.logger.warn(
    "SensemakerExt Python disabled: python_present=#{python_present}, " \
    "cli_present=#{cli_present}, cli=#{cli}"
  )
  false
end

if sensemaker_ext_python_ready?
  I18n.load_path += Dir[Rails.root.join("lib/sensemaker_ext/locales/*.yml")]
  I18n.load_path.uniq!
  SensemakerExt::Loader.install!
end
