$gen = Random.new

class State
  attr_reader :talents, :base_versatility, :base_haste
  attr_accessor :cooldowns, :faeline, :teachings, :empowered_rsks,
                :invokers_delight_time_remaining,
                :secret_infusion_time_remaining

  def initialize(talents)
    @base_versatility = 0
    @base_haste = 0
    @base_critical_strike = 0
    @talents = Hash.new(false).merge(talents)

    @cooldowns = Hash.new(0)
    @faeline = true
    @teachings = 0
    @empowered_rsks = 0
    @invokers_delight_time_remaining = 0
    @secret_infusion_time_remaining = 0
  end

  def attack_power
    2174
  end

  def spell_power
    2091
  end

  def weapon_dps
    380.97
  end

  def versatility
    @base_versatility + @secret_infusion_time_remaining > 0 ? 0.15 : 0
  end

  def haste
    @base_haste + @invokers_delight_time_remaining > 0 ? 0.3 : 0
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

  def gcd
    1.5 / (1 + haste)
  end

  def tick_gcd
    @cooldowns.transform_values! { _1 - 1.5 }
    @secret_infusion_time_remaining -= gcd
    @invokers_delight_time_remaining -= gcd
  end

  def to_s
    [@faeline, @teachings, @cooldowns].map(&:to_s).join(", ")
  end
end

class Ability
  attr_accessor :name, :power_scaling, :cooldown, :physical_school, :targets

  def initialize(name:, ap_scaling: 0, sp_scaling: 0, mw_modifier: 0, cooldown: 0, max_targets: 1, physical_school: true)
    @name = name
    @ap_scaling = ap_scaling
    @sp_scaling = sp_scaling
    @mw_modifier = mw_modifier
    @cooldown = cooldown
    @max_targets = max_targets
    @physical_school = physical_school
  end

  def cast(state, num_targets)
    base_damage = @ap_scaling * state.attack_power + @sp_scaling * state.spell_power
    base_damage += base_damage * @mw_modifier
    targets_hit = [num_targets, @max_targets].min
    armor_reduction = @physical_school ? 0.735 : 1
    vers_multiplier = 1 + state.versatility
    crit_multipler = 1 + state.critical_strike
    xuen_multiplier = state.talents['Ferocity of Xuen'] ? 1.04 : 1
    base_damage * targets_hit * armor_reduction * vers_multiplier * crit_multipler * xuen_multiplier
  end

  def side_effects(state, num_targets) end
end

class TigerPalm < Ability
  def cast(state, num_targets)
    super * (state.faeline ? 2 : 1)
  end

  def side_effects(state, num_targets)
    return unless state.talents['Teachings']
    increase = state.faeline ? 2 : 1
    state.teachings = [3, state.teachings + increase].min
  end
end

class BlackoutKick < Ability
  def cast(state, num_targets)
    @max_targets = state.faeline ? 3 : 1
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
    rsk_reset_probability += 0.6 if state.faeline
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
    state.empowered_rsks -= 1
    state.cooldowns['Thunder Focus Tea'] = 30
    state.secret_infusion_time_remaining = 10 if state.talents['Secret Infusion']
  end
end

class SpinningCraneKick < Ability
  def cast(state, num_targets)
    fast_feet_multiplier = state.talents['Fast Feet'] ? 1.7 : 1
    base = super * fast_feet_multiplier
    base *= Math.sqrt(5.0 / num_targets) if num_targets > 5
    base
  end
end

class FaelineStomp < Ability
  def side_effects(state, num_targets)
    state.faeline = true
  end
end

class Invoke < Ability
  def side_effects(state, num_targets)
    state.cooldowns[name] = 60 if state.talents['Gift of the Celestials']
    state.invokers_delight_time_remaining = 8 if state.talents['Invokers Delight']
  end
end

class Iteration
  attr_reader :damage, :history

  def initialize(talents)
    @state = State.new(talents)
    @damage = 0
    @history = []
    @time_elapsed = 0
  end

  def run(num_targets, duration, strategy)
    @time_elapsed = 0
    until @time_elapsed >= duration
      ability = strategy.logic.call(@state)
      throw "Chose ability on cooldown" if @state.cooldowns[ability.name] > 0

      if ability.name == 'Rising Sun Kick' && @state.cooldowns['Thunder Focus Tea'] <= 0
        @state.empowered_rsks += 1
        @state.empowered_rsks += 1 if @state.talents['Focused Thunder']

        @state.cooldowns['Thunder Focus Tea'] = Float::INFINITY
        @history << ['Thunder Focus Tea']
      end

      @state.cooldowns[ability.name] = ability.cooldown

      damage = ability.cast(@state, num_targets).round
      ability.side_effects(@state, num_targets)

      @damage += damage
      @damage += @state.weapon_dps * @state.gcd
      @history << [ability.name, damage]

      @time_elapsed += @state.gcd
      @state.tick_gcd
    end
  end

  def dps
    (@damage / @time_elapsed).round
  end

  def print
    @history.each do |h|
      puts h.join(' - ')
    end
    puts
    puts "Damage: #{damage.round}"
    puts "DPS: #{dps}"
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

Strategy = Struct.new(:name, :talents, :random?, :logic)
Result = Struct.new(:strategy, :best_iteration, :dps)

tiger_palm = TigerPalm.new(name: 'Tiger Palm', ap_scaling: 0.27027, mw_modifier: 1)
blackout_kick = BlackoutKick.new(name: 'Blackout Kick', ap_scaling: 0.847, mw_modifier: -0.15, cooldown: 3)
rsk = RisingSunKick.new(name: 'Rising Sun Kick', ap_scaling: 1.438, mw_modifier: 0.38, cooldown: 12)
sck = SpinningCraneKick.new(name: 'Spinning Crane Kick', ap_scaling: 0.4, mw_modifier: 1.35, max_targets: Float::INFINITY)
zen_pulse = Ability.new(name: 'Zen Pulse', sp_scaling: 1.37816, cooldown: 30, max_targets: Float::INFINITY, physical_school: false)
chi_burst = Ability.new(name: 'Chi Burst', sp_scaling: 0.46, cooldown: 30, max_targets: Float::INFINITY, physical_school: false)
faeline_stomp = FaelineStomp.new(name: 'Faeline Stomp', ap_scaling: 0.4, cooldown: 30, max_targets: 5, physical_school: false)
invoke = Invoke.new(name: 'Invoke', cooldown: 180)

default_talents = {
  'Ferocity of Xuen' => true,
  'Fast Feet' => true,
  'Teachings' => true,
  'Gift of the Celestials' => true,
  'Focused Thunder' => false,
  'Secret Infusion' => false,
  'Invokers Delight' => false,
}

no_sck_logic = ->(state) do
  return invoke if state.off_cd?(invoke.name)
  return rsk if state.off_cd?(rsk.name)
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  throw "???"
end

no_sck = Strategy.new('No SCK', default_talents, false, no_sck_logic)

no_sck_strategies = []
talents_to_test = ['Focused Thunder', 'Secret Infusion', 'Invokers Delight']
combos = (0..talents_to_test.size).flat_map { talents_to_test.combination(_1).to_a }
combos.each do |talents_enabled|
  name = 'No SCK ' + talents_enabled.join(' + ')
  talents = default_talents.merge(talents_enabled.to_h { [_1, true] })
  no_sck_strategies << Strategy.new(name, talents, false, no_sck_logic)
end

secret_infusion = Strategy.new('No SCK Infusion', default_talents, false, ->(state) do
  return rsk if state.off_cd?(rsk.name) && state.empowered_rsks > 0
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  throw "!!!"
end)

tiger_blackout = Strategy.new('Tiger Blackout', default_talents, false, ->(state) do
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  return tiger_palm
end)

sck_rsk = Strategy.new('SCK RSK Infusion', default_talents, false, ->(state) do
  return rsk if state.off_cd?(rsk.name) && state.empowered_rsks > 0
  return sck
end)

sck_only = Strategy.new('SCK only', default_talents, false, ->(_state) do
  return sck
end)

all_random = Strategy.new('All random', default_talents, true, ->(state) do
  [blackout_kick, rsk, sck].select { state.off_cd?(_1.name) }.sample
end)

no_sck_random = Strategy.new('RSK random', default_talents, true, ->(state) do
  [tiger_palm, blackout_kick, rsk].select { state.off_cd?(_1.name) }.sample
end)

strategies = [
  *no_sck_strategies,
# no_sck,
# secret_infusion,
# tiger_blackout,
# sck_rsk,
# sck_only,
# all_random,
# no_sck_random,
]

s = Time.new
duration = 60
iterations = 10000
total_iter_count = 0

seed = Random.new_seed
(1..1).each do |num_targets|
  puts "#{num_targets} targets"
  results = strategies.map do |strategy|
    $gen = Random.new(seed)
    sim = Simulation.new(num_targets, duration, iterations, strategy)
    sim.run
    total_iter_count += iterations
    Result.new(strategy, sim.best_iteration, sim.average_dps)
  end

  results = results.sort_by(&:dps).reverse

  best_result = results.first
  results.each do |result|
    puts "#{result == best_result ? '> ' : ''}#{result.strategy.name}: #{result.dps} dps"
  end

  # results.each do |result|
  #   puts
  #   puts result.strategy.name
  #   result.best_iteration.print
  # end
  puts
  best_result.best_iteration.print
  puts
end

puts
execution_time = Time.new - s
iter_per_sec = (total_iter_count / execution_time).round
puts "#{total_iter_count} iterations in #{execution_time}s, #{iter_per_sec} iter/s"

