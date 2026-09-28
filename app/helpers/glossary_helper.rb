# frozen_string_literal: true

# The game's words, explained where they're used (and all together on the
# How to play page). They're JRPG words, kept on purpose; the definition says
# what they do, with the nearest D&D idea where that helps.
module GlossaryHelper
  GLOSSARY = {
    "max_hp" => [ "HP", "Hit points. At 0 you're down (knocked out, not dead) until someone revives you." ],
    "max_mp" => [ "MP", "Magic points: one pool that pays for spells and some skills. Like spell slots, but you spend points." ],
    "str" => [ "Str", "Strength. How hard your weapon, fists and physical skills hit. (D&D: Str)" ],
    "mag" => [ "Mag", "Magic. How hard your spells hit and how much your healing heals. (D&D: your casting stat)" ],
    "vit" => [ "Vit", "Vitality. Toughness: more HP as you level. (D&D: Con)" ],
    "spr" => [ "Spr", "Spirit. Shrugging off magic and statuses like sleep or poison. (D&D: Wis saves)" ],
    "agi" => [ "Agi", "Agility. Who acts first, dodging, stealing and running away. (D&D: Dex)" ],
    "atk" => [ "Atk", "Attack: the power your weapon adds to your Str." ],
    "def" => [ "Def", "Defense: armour that softens physical hits. (D&D: AC, roughly)" ],
    "mdef" => [ "MDef", "Magic defense: what softens spells." ],
    "exp" => [ "EXP", "Experience. Winning fights gives it; enough of it is a new level, and every stat grows." ],
    "abp" => [ "ABP", "Ability points: experience for your job. Each win gives some; they level the job, from 1 to 100." ],
    "job" => [ "Job", "Your class, and you can change it between fights. Each job keeps its own level, so nothing is lost by trying another." ],
    "job_level" => [ "Job level", "How far you've got in a job, 1 to 100. Its abilities come at set levels; the climb after them is mastery." ],
    "ability_slots" => [ "Ability slots", "Room to bring abilities you learned in other jobs into this one." ],
    "gil" => [ "Gil", "Money. The party shares one purse." ],
    "type" => [ "Type", "Fire, water, ghost and the rest. A move's type against a monster's type can do double damage, half, or nothing. Your job has a type too: you take hits as it, and your Attack strikes with it. See the type chart." ],
    "desperation" => [ "Desperation move", "At a quarter HP or less, your Attack sometimes becomes your job's big move. Once a battle." ],
    "auto" => [ "Auto", "Your character repeats their last command (or attacks) every round, so you can talk. Pick a command to take over again." ],
    "check" => [ "Check", "The GM asks you to try something: your stat against a difficulty, rolled from the campaign's dice." ],
    "field_ability" => [ "Field ability", "Your job's move outside battle, like Pick Lock or Scout. Ask for it at the table; the GM says yes or no, then you roll. Once per rest." ],
    "skill" => [ "Skill", "What a check is about: Stealth, Lore, climbing. Each rides on a stat, and a job that's good at it adds +15. Every world has its own." ],
    "signature" => [ "Signature command", "Each job's own command, always on its menu: a Knight's Cover, a Thief's Mug, a Dragoon's Jump." ],
    "passive" => [ "Passive", "Something a job does on its own, like Counter or Regen. Master the job and you keep it in every job." ],
    "mastery" => [ "Mastery", "Each ability grows stronger for 40 job levels after you learn it, up to half again. Used in its own job, it's a quarter stronger still." ],
    "mastered" => [ "Mastered", "An ability at full strength, or a job at level 100 with all of them. A mastered job's passive is yours for good, whatever job you're in." ],
    "terrain" => [ "Terrain", "Where the fight is. A forest is grass, a crypt is ghost, the sea is water: a Geomancer's arts take its type." ]
  }.freeze

  PASSIVES = {
    "counter" => [ "Counter", "Hit by an enemy's blow, sometimes strike straight back." ],
    "regen" => [ "Regen", "A little HP back at the end of each of your turns." ],
    "mp_regen" => [ "Clear Mind", "A little MP back at the end of each of your turns." ],
    "first_strike" => [ "First Strike", "In the first round of a fight, you go before anyone." ],
    "second_wind" => [ "Second Wind", "Once a battle, get back up at a quarter HP when knocked down." ]
  }.freeze

  def passive_term(key)
    label, definition = PASSIVES.fetch(key.to_s) { return key.to_s.humanize }
    tag.span(label, class: "gloss", tabindex: 0, data: { gloss: definition }, aria: { label: "#{label}: #{definition}" })
  end

  # The word, with its definition on hover, or on tap on a phone.
  def gloss(key, text = nil)
    label, definition = GLOSSARY.fetch(key.to_s) { return text || key.to_s.humanize }
    label = worlds_label(key.to_s) || label
    tag.span(text || label, class: "gloss", tabindex: 0, data: { gloss: definition }, aria: { label: "#{text || label}: #{definition}" })
  end

  # The world's own word for a glossary term, if it has one (Vocabulary).
  def worlds_label(key)
    case key
    when "gil" then word("currency").upcase_first
    when "max_hp" then word("hp")
    when "max_mp" then word("mp")
    when *Vocabulary::STATS then word("stat.#{key}")
    end
  end

  # A stat's short name, explained.
  def stat_term(name)
    gloss(name, stat_label(name))
  end
end
