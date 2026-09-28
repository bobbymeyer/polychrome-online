# frozen_string_literal: true

# What the game says when it won't do something: "The party has 40 gil;
# a Potion costs 50", "Not while a battle is on". Raised by models, shown to
# whoever asked (ApplicationController rescues it into an alert), and never
# confused with a programmer's mistake: an ArgumentError is a bug and
# should crash.
class Refusal < StandardError; end
