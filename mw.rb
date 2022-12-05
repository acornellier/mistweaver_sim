$gen = Random.new

ARMOR_RESISTANCE = 0.735

# RESONANT_FISTS = 'Resonant Fists'
SUMMON_WHITE_TIGER_STATUE = 'Summon White Tiger Statue'
TEACHINGS = 'Teachings'
FAELINE_STOMP = 'Faeline Stomp'
GIFT_OF_THE_CELESTIALS = 'Gift of the Celestials'
INVOKERS_DELIGHT = 'Invokers Delight'
SECRET_INFUSION = 'Secret Infusion'
BONEDUST_BREW = 'Bonedust Brew'
ATTENUATION = 'Attenuation'
TEA_OF_PLENTY = 'Tea of Plenty'
FOCUSED_THUNDER = 'Focused Thunder'

class State
  attr_reader :talents, :base_versatility, :base_haste,
              :time, :history, :damage, :total_weapon_damage, :total_white_tiger_damage
  attr_accessor :cooldowns, :buffs, :teachings, :first_tft_empower_available, :empowered_rsks

  def initialize(talents)
    @base_versatility = 0.0998
    @base_haste = 0.1182
    @base_critical_strike = 0.1508
    @talents = Hash.new(false).merge(talents)

    @time = 0
    @history = []
    @damage = 0
    @total_weapon_damage = 0
    @total_white_tiger_damage = 0

    @cooldowns = Hash.new(0)
    @buffs = Hash.new(0)
    @faeline = false
    @teachings = 0
    @empowered_rsks = 0
    @first_tft_empower_available = false
  end

  def cast_ability(ability, num_targets)
    throw "Cannot cast ability on cooldown" if on_cd?(ability.name)

    cooldowns[ability.name] = ability.hasted_cooldown(self)

    damage = ability.cast(self, num_targets).round
    ability.side_effects(self, num_targets)

    gcd = ability.gcd / (1 + haste)

    weapon_damage = weapon_dps * gcd * damage_multiplier
    white_tiger_damage = white_tiger_dps(num_targets) * gcd * damage_multiplier

    @total_weapon_damage += weapon_damage
    @total_white_tiger_damage += white_tiger_damage
    @damage += damage + weapon_damage + white_tiger_damage
    @history << [ability.name, damage]

    @cooldowns.transform_values! { _1 - gcd }
    @buffs.transform_values! { _1 - gcd }
    @time += gcd
  end

  def attack_power
    6764
  end

  def spell_power
    6504
  end

  def weapon_dps
    1582.24
  end

  def versatility
    @base_versatility + secret_infusion_increase
  end

  def haste
    invokers_delight_increase = buff_active?(INVOKERS_DELIGHT) ? 0.33 : 0
    @base_haste + invokers_delight_increase
  end

  def critical_strike
    @base_critical_strike
  end

  def on_cd?(ability_name)
    @cooldowns[ability_name] > 0.01
  end

  def off_cd?(ability_name)
    !on_cd?(ability_name)
  end

  def buff_active?(buff_name)
    @buffs[buff_name] > 0
  end

  def buff_inactive?(buff_name)
    !buff_active?(buff_name)
  end

  def damage_multiplier
    vers_multiplier = 1 + versatility
    crit_multipler = 1 + critical_strike
    xuen_multiplier = talents['Ferocity of Xuen'] ? 1.04 : 1
    bdb_multiplier = buff_active?(BONEDUST_BREW) ? 1.25 : 1
    bdb_multiplier *= 1.2 if talents[ATTENUATION] && buff_active?(BONEDUST_BREW)
    vers_multiplier * crit_multipler * xuen_multiplier * bdb_multiplier
  end

  def white_tiger_dps(num_targets)
    return 0 unless buff_active?(SUMMON_WHITE_TIGER_STATUE)
    attack_power_scaling = 0.25
    time_between_pulses = 2
    attack_power_scaling * attack_power * num_targets / time_between_pulses
  end

  def secret_infusion_increase
    return 0 unless buff_active?(SECRET_INFUSION)
    { 1 => 0.08, 2 => 0.15 }.fetch(talents[SECRET_INFUSION])
  end
end

class Ability
  attr_reader :name, :gcd, :required_talent

  def initialize(name:, ap_scaling: 0, sp_scaling: 0, mw_modifier: 0, cooldown: 0, max_targets: 1,
                 physical_school: true, haste_flagged: false, gcd: 1.5, required_talent: nil)
    @name = name
    @ap_scaling = ap_scaling
    @sp_scaling = sp_scaling
    @mw_modifier = mw_modifier
    @cooldown = cooldown
    @max_targets = max_targets
    @physical_school = physical_school
    @haste_flagged = haste_flagged
    @gcd = gcd
    @required_talent = required_talent
  end

  def cast(state, num_targets)
    base_damage = @ap_scaling * state.attack_power + @sp_scaling * state.spell_power
    base_damage += base_damage * @mw_modifier
    targets_hit = [num_targets, @max_targets].min
    armor_reduction = @physical_school ? ARMOR_RESISTANCE : 1
    base_damage * targets_hit * armor_reduction * state.damage_multiplier
  end

  def side_effects(state, num_targets) end

  def hasted_cooldown(state)
    haste_multiplier = @haste_flagged ? 1.0 / (1 + state.haste) : 1
    @cooldown * haste_multiplier
  end
end

class TigerPalm < Ability
  def cast(state, num_targets)
    super * (state.buff_active?(FAELINE_STOMP) ? 2 : 1)
  end

  def side_effects(state, num_targets)
    return unless state.talents[TEACHINGS]
    increase = state.buff_active?(FAELINE_STOMP) ? 2 : 1
    state.teachings = [3, state.teachings + increase].min
  end
end

class BlackoutKick < Ability
  def cast(state, num_targets)
    @max_targets = state.buff_active?(FAELINE_STOMP) ? 3 : 1
    super * (1 + state.teachings)
  end

  def side_effects(state, num_targets)
    reset_probability = rsk_any_reset_probability(state, num_targets)
    state.cooldowns['Rising Sun Kick'] = 0 if $gen.rand < reset_probability
    state.teachings = 0
  end

  def rsk_any_reset_probability(state, num_targets)
    hits = [num_targets, @max_targets].min * (1 + state.teachings)
    rsk_reset_probability = 0.15
    rsk_reset_probability += 0.6 if state.buff_active?(FAELINE_STOMP)
    1 - rsk_reset_probability ** hits
  end
end

class RisingSunKick < Ability
  def cast(state, num_targets)
    fast_feet_multiplier = state.talents['Fast Feet'] ? 1.7 : 1
    super * fast_feet_multiplier
  end

  def side_effects(state, num_targets)
    return unless state.empowered_rsks > 0
    state.cooldowns[name] -= 9
    state.first_tft_empower_available = false
    state.empowered_rsks -= 1
    state.cooldowns['Thunder Focus Tea'] = 30
    state.buffs[SECRET_INFUSION] = 10 if state.talents[SECRET_INFUSION]
  end
end

class SpinningCraneKick < Ability
  def cast(state, num_targets)
    fast_feet_multiplier = state.talents['Fast Feet'] ? 1.1 : 1
    base = super * fast_feet_multiplier
    base *= Math.sqrt(5.0 / num_targets) if num_targets > 5
    base
  end
end

class FaelineStomp < Ability
  def side_effects(state, num_targets)
    state.buffs[FAELINE_STOMP] = 30
  end
end

class Invoke < Ability
  def side_effects(state, num_targets)
    state.cooldowns[name] = 60 if state.talents[GIFT_OF_THE_CELESTIALS]
    return unless state.talents[INVOKERS_DELIGHT]
    state.buffs[INVOKERS_DELIGHT] = state.talents[GIFT_OF_THE_CELESTIALS] ? 8 : 20
  end
end

class BonedustBrew < Ability
  def side_effects(state, num_targets)
    state.buffs[BONEDUST_BREW] = 10
  end
end

class SummonWhiteTigerStatue < Ability
  def side_effects(state, num_targets)
    state.buffs[SUMMON_WHITE_TIGER_STATUE] = 30
  end
end

class ThunderFocusTea < Ability
  def side_effects(state, num_targets)
    state.first_tft_empower_available = true
    state.empowered_rsks += 1
    state.empowered_rsks += 1 if state.talents[FOCUSED_THUNDER]
    if state.talents[TEA_OF_PLENTY]
      2.times do
        state.empowered_rsks += 1 if $gen.rand > (1 / 3)
      end
    end
  end
end

class Iteration
  def initialize(talents)
    @state = State.new(talents)
    @damage = 0
    @history = []
    @total_weapon_damage = 0
    @time_elapsed = 0
  end

  def run(num_targets, duration, strategy)
    until @state.time >= duration
      ability = strategy.logic.find do |ability_, condition|
        @state.off_cd?(ability_.name) &&
          (ability_.required_talent.nil? || @state.talents[ability_.required_talent]) &&
          (condition.nil? || condition.call(@state))
      end
      ability = ability.first if ability.is_a?(Array)
      @state.cast_ability(ability, num_targets)
    end
  end

  def damage
    @state.damage
  end

  def dps
    (@state.damage / @state.time).round
  end

  def print_stats
    puts "Damage: #{@state.damage.round}"
    puts "DPS: #{@state.dps}"
    puts "Weapon: #{(@total_weapon_damage / @state.time).round} dps"
    @state.history.group_by { _1[0] }.each do |ability_name, casts|
      ability_dps = (casts.sum { _2 || 0 } / @state.time).round
      puts "#{ability_name}: #{ability_dps} dps, #{casts.size} casts" if ability_dps > 0
    end
    puts
    @state.history.each do |h|
      puts h.join(' - ')
    end
  end
end

class Simulation
  attr_reader :iterations

  def initialize(num_targets, duration, iteration_count, strategy)
    @num_targets = num_targets
    @duration = duration
    @iteration_count = iteration_count
    @strategy = strategy
    @iterations = []
  end

  def run
    new_iterations = Array.new(@iteration_count) { Iteration.new(@strategy.talents) }
    new_iterations.each do |iteration|
      iteration.run(@num_targets, @duration, @strategy)
    end
    @iterations += new_iterations
  end

  def best_iteration
    @iterations.max_by(&:damage)
  end

  def average_dps_of_best(n)
    @iterations.max_by(n, &:dps).sum(&:dps) / [n, @iterations.size].min
  end

  def average_dps
    @iterations.sum(&:dps) / @iterations.size
  end
end

Strategy = Struct.new(:name, :talents, :logic)
Result = Struct.new(:strategy, :best_iteration, :dps)

tiger_palm = TigerPalm.new(name: 'Tiger Palm', ap_scaling: 0.27027, mw_modifier: 1)
blackout_kick = BlackoutKick.new(name: 'Blackout Kick', ap_scaling: 0.847, mw_modifier: -0.15, cooldown: 3, haste_flagged: true)
rsk = RisingSunKick.new(name: 'Rising Sun Kick', ap_scaling: 1.438, mw_modifier: 0.38, cooldown: 12, haste_flagged: true)
sck = SpinningCraneKick.new(name: 'Spinning Crane Kick', ap_scaling: 0.4, mw_modifier: 1.35, max_targets: Float::INFINITY)
zen_pulse = Ability.new(name: 'Zen Pulse', sp_scaling: 1.37816, cooldown: 30, max_targets: Float::INFINITY, physical_school: false)
chi_burst = Ability.new(name: 'Chi Burst', sp_scaling: 0.46, cooldown: 30, max_targets: Float::INFINITY, physical_school: false)
faeline_stomp = FaelineStomp.new(name: FAELINE_STOMP, ap_scaling: 0.4, cooldown: 30, max_targets: 5, physical_school: false)
bdb = BonedustBrew.new(name: BONEDUST_BREW, cooldown: 60, gcd: 1, required_talent: BONEDUST_BREW)
summon_white_tiger_statue = SummonWhiteTigerStatue.new(name: SUMMON_WHITE_TIGER_STATUE, cooldown: 120, gcd: 1, required_talent: SUMMON_WHITE_TIGER_STATUE)
invoke = Invoke.new(name: 'Invoke', cooldown: 180, gcd: 1, required_talent: INVOKERS_DELIGHT)
tft = ThunderFocusTea.new(name: 'Thunder Focus Tea', cooldown: 30, gcd: 0)

single_target = Strategy.new('ST', [], [
  tft,
  summon_white_tiger_statue,
  [faeline_stomp, -> { _1.buff_inactive?(FAELINE_STOMP) }],
  invoke,
  bdb,
  rsk,
  [tiger_palm, -> { _1.teachings <= 1 }],
  blackout_kick,
])

st_infusion_prio = Strategy.new('STI', [], [
  tft,
  summon_white_tiger_statue,
  [faeline_stomp, -> { _1.buff_inactive?(FAELINE_STOMP) }],
  invoke,
  bdb,
  [rsk, -> { _1.first_tft_empower_available && _1.talents[SECRET_INFUSION] }],
  [tiger_palm, -> { _1.teachings <= 1 }],
  blackout_kick,
])

many_target = Strategy.new('MT', [], [
  tft,
  summon_white_tiger_statue,
  invoke,
  bdb,
  zen_pulse,
  sck,
])

mt_infusion_prio = Strategy.new('MTI', [], [
  tft,
  summon_white_tiger_statue,
  invoke,
  bdb,
  [rsk, -> { _1.first_tft_empower_available && _1.talents[SECRET_INFUSION] }],
  zen_pulse,
  sck,
])

target_strategies = {
  1 => [single_target],
  2 => [single_target],
  3 => [single_target, st_infusion_prio],
  4 => [mt_infusion_prio],
  5 => [mt_infusion_prio],
}

default_talents = {
  'Ferocity of Xuen' => true,
  'Fast Feet' => true,
  SUMMON_WHITE_TIGER_STATUE => true,
  TEACHINGS => true,
  GIFT_OF_THE_CELESTIALS => true,
  TEA_OF_PLENTY => false,
  SECRET_INFUSION => false,
  INVOKERS_DELIGHT => false,
  FOCUSED_THUNDER => false,
  BONEDUST_BREW => false,
  ATTENUATION => false,
}

SECRET_INFUSION_2 = 'Secret Infusion 2'
talents_to_test = [SECRET_INFUSION, SECRET_INFUSION_2, INVOKERS_DELIGHT, TEA_OF_PLENTY, FOCUSED_THUNDER, BONEDUST_BREW, ATTENUATION]
talent_combos = talents_to_test.permutation(4).filter_map do |talents|
  next if talents.include?(ATTENUATION) && !talents.include?(BONEDUST_BREW)
  next if talents.include?(SECRET_INFUSION_2) && !talents.include?(SECRET_INFUSION)
  next if talents.include?(INVOKERS_DELIGHT) && !talents.include?(SECRET_INFUSION_2)
  talents.to_h { [_1, true] }.tap do |hash|
    hash[SECRET_INFUSION] = 1 if hash[SECRET_INFUSION]
    hash[SECRET_INFUSION] = 2 if hash.delete(SECRET_INFUSION_2)
  end
end.uniq

s = Time.new
duration = 120
iterations = 100
total_iter_count = 0
seed = Random.new_seed

(1..5).each do |num_targets|
  puts "#{num_targets} targets"

  strategies = target_strategies.fetch(num_targets)
  results = strategies.flat_map do |base_strategy|
    talent_combos.map do |talents|
      strategy = Strategy.new(base_strategy.name, default_talents.merge(talents), base_strategy.logic)

      $gen = Random.new(seed)
      sim = Simulation.new(num_targets, duration, iterations, strategy)
      sim.run
      total_iter_count += iterations
      Result.new(strategy, sim.best_iteration, sim.average_dps)
    end
  end

  pretty_talents = ->(result) do
    result.strategy.talents.filter_map do |talent, value|
      next unless value && talents_to_test.include?(talent)
      talent + (value == true ? '' : " #{value}")
    end.join(' + ')
  end

  results = results.sort_by(&:dps).reverse
  results.each.with_index do |result, idx|
    prefix = idx == 0 ? '>' : ' '
    base_name = result.strategy.name.ljust(4)
    talents = pretty_talents.call(result)
    puts "#{prefix} #{base_name} | #{talents} | #{result.dps} dps"
  end

  # results.each { |result| puts; puts [result.strategy.name, pretty_talents.call(result)].join(' | '); result.best_iteration.print_stats }
  # puts; results.first.best_iteration.print_stats
  puts
end

execution_time = Time.new - s
iter_per_sec = (total_iter_count / execution_time).round
puts "#{total_iter_count} iterations in #{execution_time}s, #{iter_per_sec} iter/s"

