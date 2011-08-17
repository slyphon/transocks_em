# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'transocks_em/version'

Gem::Specification.new do |s|
  s.name        = "slyphon-transocks_em"
  s.version     = TransocksEM::VERSION
  s.authors     = ["coderrr", "Jonathan D. Simms"]
  s.email       = ["coderrr.contact@gmail.com", "simms@hp.com"]
  s.summary     = %q{transparently tunnel connections over SOCKS5 using eventmachine and ipfw/iptables}
  s.description = s.summary

  s.required_ruby_version = '>= 1.9.2'

  s.add_runtime_dependency('logging',         '~> 1.5.1')
  s.add_runtime_dependency('eventmachine',    '~> 1.0.0.beta.3')


  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
end
