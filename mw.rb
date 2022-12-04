$gen = Random.new

FAELINE_STOMP = 'Faeline Stomp'
INVOKERS_DELIGHT = 'Invokers Delight'
SECRET_INFUSION = 'Secret Infusion'
BONEDUST_BREW = 'Bonedust Brew'
ATTENUATION = 'Attenuation'
TEA_OF_PLENTY = 'Tea of Plenty'
FOCUSED_THUNDER = 'Focused Thunder'

class State
  attr_reader :talents, :base_versatility, :base_haste
  attr_accessor :cooldowns, :buffs, :teachings, :empowered_rsks

  def initialize(talents)
    @base_versatility = 0.1843
    @base_haste = 0.1158
    @base_critical_strike = 0.0725
    @talents = Hash.new(false).merge(talents)

    @cooldowns = Hash.new(0)
    @buffs = Hash.new(0)
    @faeline = false
    @teachings = 0
    @empowered_rsks = 0
  end

  def attack_power
    6764
  end

  def spell_power
    6504
  end

  def weapon_dps
    1447.79
  end

  def versatility
    secret_infusion_increase = buff_active?(SECRET_INFUSION) ? 0.15 : 0
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

  def gcd
    1.5 / (1 + haste)
  end

  def tick_gcd
    @cooldowns.transform_values! { _1 - 1.5 }
    @buffs.transform_values! { _1 - 1.5 }
  end

  def to_s
    [@faeline, @teachings, @cooldowns].map(&:to_s).join(", ")
  end
end

class Ability
  attr_accessor :name, :power_scaling, :physical_school, :targets, :haste_flagged

  def initialize(name:, ap_scaling: 0, sp_scaling: 0, mw_modifier: 0, cooldown: 0, max_targets: 1, physical_school: true, haste_flagged: false)
    @name = name
    @ap_scaling = ap_scaling
    @sp_scaling = sp_scaling
    @mw_modifier = mw_modifier
    @cooldown = cooldown
    @max_targets = max_targets
    @physical_school = physical_school
    @haste_flagged = haste_flagged
  end

  def cast(state, num_targets)
    base_damage = @ap_scaling * state.attack_power + @sp_scaling * state.spell_power
    base_damage += base_damage * @mw_modifier
    targets_hit = [num_targets, @max_targets].min
    armor_reduction = @physical_school ? 0.735 : 1
    vers_multiplier = 1 + state.versatility
    crit_multipler = 1 + state.critical_strike
    xuen_multiplier = state.talents['Ferocity of Xuen'] ? 1.04 : 1
    bdb_multiplier = state.buff_active?(BONEDUST_BREW) ? 1.25 : 1
    bdb_multiplier *= 1.2 if state.talents[ATTENUATION] && state.buff_active?(BONEDUST_BREW)
    base_damage * targets_hit * armor_reduction * vers_multiplier * crit_multipler * xuen_multiplier * bdb_multiplier
  end

  def side_effects(state, num_targets) end

  def hasted_cooldown(state)
    haste_multiplier = haste_flagged ? 1.0 / (1 + state.haste) : 1
    @cooldown * haste_multiplier
  end
end

class TigerPalm < Ability
  def cast(state, num_targets)
    super * (state.buff_active?(FAELINE_STOMP) ? 2 : 1)
  end

  def side_effects(state, num_targets)
    return unless state.talents['Teachings']
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
    state.empowered_rsks -= 1
    state.cooldowns['Thunder Focus Tea'] = 30
    state.buffs[SECRET_INFUSION] = 10 if state.talents[SECRET_INFUSION]
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
    state.buffs[FAELINE_STOMP] = 30
  end
end

class Invoke < Ability
  def side_effects(state, num_targets)
    state.cooldowns[name] = 60 if state.talents['Gift of the Celestials']
    return unless state.talents[INVOKERS_DELIGHT]
    state.buffs[INVOKERS_DELIGHT] = state.talents['Gift of the Celestials'] ? 8 : 20
  end
end

class BonedustBrew < Ability
  def side_effects(state, num_targets)
    state.buffs[BONEDUST_BREW] = 10
  end
end

class Iteration
  attr_reader :damage, :history

  def initialize(talents)
    @state = State.new(talents)
    @damage = 0
    @history = []
    @total_weapon_damage = 0
    @time_elapsed = 0
  end

  def run(num_targets, duration, strategy)
    @time_elapsed = 0
    until @time_elapsed >= duration
      if @state.cooldowns['Thunder Focus Tea'] <= 0
        @state.empowered_rsks += 1
        @state.empowered_rsks += 1 if @state.talents[FOCUSED_THUNDER]
        if @state.talents[TEA_OF_PLENTY]
          2.times do
            @state.empowered_rsks += 1 if $gen.rand > 1 / 3
          end
        end

        @state.cooldowns['Thunder Focus Tea'] = Float::INFINITY
        @history << ['Thunder Focus Tea']
      end

      ability = strategy.logic.call(@state)
      throw "Chose ability on cooldown" if @state.on_cd?(ability.name)

      @state.cooldowns[ability.name] = ability.hasted_cooldown(@state)

      damage = ability.cast(@state, num_targets).round
      ability.side_effects(@state, num_targets)

      @damage += damage
      @history << [ability.name, damage]

      weapon_damage = @state.weapon_dps * @state.gcd
      @total_weapon_damage += weapon_damage
      @damage += weapon_damage

      @time_elapsed += @state.gcd
      @state.tick_gcd
    end
  end

  def dps
    (@damage / @time_elapsed).round
  end

  def print_stats
    puts "Damage: #{damage.round}"
    puts "DPS: #{dps}"
    puts "Weapon: #{(@total_weapon_damage / @time_elapsed).round}"
    @history.group_by { _1[0] }.each do |ability_name, casts|
      ability_dps = (casts.sum { _2 || 0 } / @time_elapsed).round
      puts "#{ability_name}: #{ability_dps} dps, #{casts.size} casts" if ability_dps > 0
    end
    puts
    @history.each do |h|
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
bdb = BonedustBrew.new(name: BONEDUST_BREW, cooldown: 60)
invoke = Invoke.new(name: 'Invoke', cooldown: 180)

buffs_logic = ->(state) do
  return bdb if state.off_cd?(bdb.name) && state.talents[BONEDUST_BREW]
  return invoke if state.off_cd?(invoke.name) && state.talents[INVOKERS_DELIGHT]
end

single_target = Strategy.new('ST', [], ->(state) do
  return faeline_stomp unless state.buff_active?(FAELINE_STOMP)
  buff_res = buffs_logic.call(state)
  return buff_res if buff_res
  return rsk if state.off_cd?(rsk.name)
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  throw "???"
end)
st_infusion_prio = Strategy.new('STI', [], ->(state) do
  return faeline_stomp unless state.buff_active?(FAELINE_STOMP)
  buff_res = buffs_logic.call(state)
  return buff_res if buff_res
  return rsk if state.off_cd?(rsk.name) && state.empowered_rsks > 0
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  throw "!!!"
end)

tiger_blackout = Strategy.new('TB', [], ->(state) do
  return faeline_stomp if state.off_cd?(faeline_stomp.name)
  buff_res = buffs_logic.call(state)
  return buff_res if buff_res
  return tiger_palm if state.teachings <= 1
  return blackout_kick if state.off_cd?(blackout_kick.name)
  return tiger_palm
end)

many_target = Strategy.new('MT', [], ->(state) do
  buff_res = buffs_logic.call(state)
  return buff_res if buff_res
  return sck
end)
mt_infusion_prio = Strategy.new('MTI', [], ->(state) do
  buff_res = buffs_logic.call(state)
  return buff_res if buff_res
  return rsk if state.off_cd?(rsk.name) && state.empowered_rsks > 0
  return sck
end)

all_random = Strategy.new('All random', [], ->(state) do
  [blackout_kick, rsk, sck].select { state.off_cd?(_1.name) }.sample
end)
no_sck_random = Strategy.new('RSK random', [], ->(state) do
  [tiger_palm, blackout_kick, rsk].select { state.off_cd?(_1.name) }.sample
end)

target_strategies = {
  1 => [single_target],
  2 => [single_target],
  3 => [single_target, st_infusion_prio],
  4 => [mt_infusion_prio, many_target],
  5 => [mt_infusion_prio, many_target,],
}

default_talents = {
  'Ferocity of Xuen' => true,
  'Fast Feet' => true,
  'Teachings' => true,
  'Gift of the Celestials' => true,
  SECRET_INFUSION => true,
  INVOKERS_DELIGHT => false,
  TEA_OF_PLENTY => false,
  FOCUSED_THUNDER => false,
  BONEDUST_BREW => false,
  ATTENUATION => false,
}

talents_to_test = [INVOKERS_DELIGHT, BONEDUST_BREW, TEA_OF_PLENTY, FOCUSED_THUNDER, ATTENUATION]
talent_combos = [true, false].repeated_permutation(talents_to_test.size).map do |bools|
  talents_to_test.each.with_index.to_h do |talent, idx|
    [talent, bools[idx]]
  end
end

def enable_talents(*talents)
  talents.to_h { [_1, true] }
end

talent_combos = [
  {},
  enable_talents(INVOKERS_DELIGHT, FOCUSED_THUNDER),
  enable_talents(INVOKERS_DELIGHT, TEA_OF_PLENTY),
  enable_talents(FOCUSED_THUNDER, TEA_OF_PLENTY),
  enable_talents(BONEDUST_BREW, ATTENUATION),
]

s = Time.new
duration = 60
iterations = 100
total_iter_count = 0
seed = Random.new_seed

(5..5).each do |num_targets|
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

  results = results.sort_by(&:dps).reverse
  results.each.with_index do |result, idx|
    prefix = idx == 0 ? '>' : ' '
    base_name = result.strategy.name.ljust(4)
    talents = result.strategy.talents.select { _2 && talents_to_test.include?(_1) }.keys.join(' + ')
    puts "#{prefix} #{base_name} | #{talents} | #{result.dps} dps"
  end

  # results.each do |result|
  #   puts
  #   puts result.strategy.name
  #   result.best_iteration.print_stats
  # end
  # puts
  # results.first.best_iteration.print_stats
  puts
end

execution_time = Time.new - s
iter_per_sec = (total_iter_count / execution_time).round
puts "#{total_iter_count} iterations in #{execution_time}s, #{iter_per_sec} iter/s"

