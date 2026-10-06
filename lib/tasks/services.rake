# frozen_string_literal: true

namespace :services do
  desc "Check the app can reach the language model, if one is set, step by step"
  task check: :environment do
    puts "In a container: #{ConnectionCheck.in_container? ? 'yes' : 'no'}"
    doctor = ConnectionCheck.llm
    if doctor
      doctor.steps.each { |step| puts "#{step.ok ? '  ok ' : 'FAIL '} #{step.label}: #{step.detail}" }
    else
      puts "No language model is set (LLM_URL, or the Settings page)."
    end
  end
end
