# frozen_string_literal: true

require "e2e_helper"

LemansReport.base_credit = 0.6

require "suites/authoring"
require "suites/import_export"
require "suites/game"
require "suites/scoring"
require "suites/timer"
require "suites/security"
require "suites/restart"
require "suites/own_tests"
require "suites/edge_cases"
