# frozen_string_literal: true

namespace :comfy do
  desc "Check the app can reach ComfyUI (and the language model, if set), step by step"
  task doctor: :environment do
    puts "In a container: #{Comfy::Doctor.in_container? ? 'yes' : 'no'}"
    [ Comfy::Doctor.comfy, Comfy::Doctor.llm ].compact.each do |doctor|
      doctor.steps.each { |step| puts "#{step.ok ? '  ok ' : 'FAIL '} #{step.label}: #{step.detail}" }
      puts
    end
  end
end
