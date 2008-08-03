#
# :title: Truco Game Plugin for rbot
#
# Author:: Marcos Piccinini <nofxx>
# Copyright:: (C) 2008 Marcos Piccinini
# License:: GPL v2
#
# Adaptation of:
# Uno Game Plugin for rbot
# Author:: Giuseppe "Oblomov" Bilotta <giuseppe.bilotta@gmail.com>
# Copyright:: (C) 2008 Giuseppe Bilotta
# License:: GPL v2
#
#
# Truco: You start with 3 cards. The values are as shown in the table. 
# The one who wins two hands, wins a point.
# If the first one drawns, the next one must decide (the most valuable card wins)
# You can play with 2, 4 or 6 ppl.
#
#
# # # # # # # # # # # # # # 
#
#   TrucoGame
#
class TrucoGame
  NAIPES = %w{Ouro Copas Espada Paus}
  SPECIALS = %w{Zap SeteCopas Espadilha SeteOuro}
  VALUES  = %w{3 2 A K J Q 7 6 5 4}
  ORDER = SPECIALS.concat(VALUES)

  # cards in stock
  attr_reader :stock
  # current discard
  attr_reader :discard
  # previous discard, in case of challenge
  attr_reader :last_discard
  # channel the game is played in
  attr_reader :channel
  # list of players
  attr :players
  # game start time
  attr :start_time
  # the IRC user that created the game
  attr_accessor :manager
  # who call the last truco!
  attr_accessor :called_truco

  def TrucoGame.color_map(clr)
    case clr
    when 'Ouro'   then :red
    when 'Copas'  then :white
    when 'Espada' then :black
    when 'Paus'   then :white
    end
  end

  def TrucoGame.irc_naipe_bg(clr)
    cor = case clr
    when 'Ouro'   then :white
    when 'Copas'  then :red
    when 'Espada' then :white
    when 'Paus'   then :black
    end
    Irc.color(cor, TrucoGame.color_map(clr))
  end

  def TrucoGame.irc_naipe_fg(clr)
    Irc.color(TrucoGame.color_map(clr))
  end

  def TrucoGame.colorify(str, fg=false)
    ret = Bold.dup
    str.length.times do |i|
      ret << (fg ?
      TrucoGame.irc_naipe_fg(NAIPES[i%4]) :
      TrucoGame.irc_naipe_bg(NAIPES[i%4]) ) +str[i,1]
    end
    ret << NormalText
  end

  def TrucoGame.simbolizar(n)
    case n
    when 'Copas'  then  "♥"
    when 'Ouro'   then  "♦"
    when 'Paus'   then  "♣"
    when 'Espada' then  "♠"
    end
  end
  
  def announce(msg, opts={})
    @bot.say channel, msg, opts
  end

  def notify(player, msg, opts={})
    @bot.notice player.user, msg, opts
  end

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #
  #
  #  INIT
  #
  TRUCO = TrucoGame.colorify('TRUCO!', true)

  def initialize(plugin, channel, manager, round_value, end_game)
    @channel = channel
    @plugin = plugin
    @bot = plugin.bot
    @players = []
    @dropouts = []
    @value = nil
    @naipe = nil
    make_base_stock
    @stock = []
    make_stock
    @hands = []
    @rounds = []
    @turns = 0
    @called_truco = nil
    @accept_truco = false
    @top_card = nil
    @top_card_owner = nil
    @score = []
    @start_time = nil
    @join_timer = nil
    @manager = manager
    @round_value = round_value ? round_value : 1 
    @round_value_default = @round_value
    @round_value_end = end_game ? end_game : 11
  end

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  CARD
  #
  class Card
    attr_reader :naipe
    attr_reader :value
    attr_reader :shortform
    attr_reader :to_s
    attr_reader :score

    def initialize(c)
      raise unless NAIPES.include? c[0]
      raise unless ORDER.include? c[1]
      @naipe = c[0].dup
      @value = c[1].dup
      @shortform = (@naipe[0,1]+@value.to_s[0,1]).downcase

      @to_s = TrucoGame.irc_naipe_bg(@naipe) +
        Bold + ["|", @value, TrucoGame.simbolizar(@naipe), @naipe, '|'].join(' ') + NormalText
    end

    def <=>(other)
      return  ORDER.index(other.value) <=> ORDER.index(self.value)
    end
    include Comparable
  end

  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  PLAYER
  #
  class Player
    attr_accessor :cards
    attr_accessor :user
    attr_accessor :score

    def initialize(user)
      @user = user
      @cards = []
      @score = 0
    end
    def has_card?(short)
      has = nil
      @cards.each { |c|
        has = c if c.shortform == short
      }
      if has.empty?
        return false
      else
        return has
      end
    end
    def to_s
      Bold + @user.to_s + Bold
    end
    def score(score = 1)
      @score += score
    end
  end

  def get_player(user)
    case user
    when User
      @players.each do |p|
        return p if p.user == user
      end
    when String
      @players.each do |p|
        return p if p.user.irc_downcase == user.irc_downcase(channel.casemap)
      end
    else
      get_player(user.to_s)
    end
    return nil
  end

  def current_player
    get_player(@players[0])
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  TEAM
  #
  class Team
    attr_accessor :name
    attr_accessor :members
    
    def initialize(name, members)
      @name = name
      @members = members
    end
    
    def to_s
      "In this team: " + Bold + @members.join[', '] + Bold
    end 
  end


  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  STOCK
  #
  def make_base_stock

    base = NAIPES.inject([]) do |list, naip|
      VALUES.each { |v| list << [naip, v] }
      list
    end

    base[base.index(%w{Paus 4})]    = ['Paus','Zap']
    base[base.index(%w{Espada A})]  = ['Espada','SeteCopas']
    base[base.index(%w{Copas 7})]   = ['Copas','Espadilha']
    base[base.index(%w{Ouro 7})]    = ['Ouro','SeteOuro']

    @base_stock = base.inject([]) do |ll, f|
      ll << Card.new(f)
    end
  end

  def make_stock
    @stock.replace @base_stock
    # remove the cards in the players hand
    @players.each { |p| p.cards.each { |c| @stock.delete_one c } }
    # remove current top discarded card if present
    if @discard
      @stock.delete_one(discard)
    end
    @stock.shuffle!
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  START GAME
  #
  def start_game#(num_players)

    if @players.length == 3 or @players.length == 5
      announce _("%{p} you are out!!") % { :p => @players.last }
      drop_player(@players.last)
    end
    @players.shuffle!
    @players.each { |p| show_user_cards(p) }
    show_order
    announce _("%{p} começa o jogo!! mão %{n}") % {
      :p => @players.first,
      :n => @hands.length + 1
    }
    #card = @stock.shift
    #set_discard(card)
    #show_discard
    show_turn
    @start_time = Time.now

  end

  def elapsed_time
    if @start_time
      Utils.secs_to_string(Time.now-@start_time)
    else
      _("no time")
    end
  end

  def set_discard(card)
    @discard = card
    @value = card.value.dup rescue card.value
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  TABLE
  #
  def clean_table
    @turns = 0
    @top_card = nil
    @top_card_owner = nil
  end

  def next_turn(kind = nil,opts={})
    case kind
    when nil
      @players << @players.shift

    when :hand
      announce _("%{p} ganhou essa mão com %{card}.") % { 
        :p => @top_card_owner, 
        :card => @top_card
      }
      @hands << @top_card_owner#, @top_card]
      @players += @players.shift(@players.index(@top_card_owner))
      clean_table

    when :round
      
      @top_card_owner.score(@round_value)
      @round_value = @round_value_default
      if @top_card_owner.score > @round_value_end
        announce _("%{p} ganhou essa partida!!!!.") % { 
          :p => @top_card_owner, 
          :s => @top_card_owner.score
        }
        end_game(true)
      end
      
      @players.each { |p| deal(p, 3) }
      @rounds << @hands
      @hands = []
      @players << @players.shift
      announce _("%{p} ganhou essa rodada e tem agora %{s} pontos.") % { 
        :p => @top_card_owner, 
        :s => @top_card_owner.score
      }
      clean_table
    end

    show_turn
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  PLAY 
  #
  def get_card(source, card)
    p = get_player(source)
    return nil unless p
    unless card =~ /1|2|3/
      shorts = card.gsub(/\s+/,'').match(/^(?:([ceop]\+?\S){1,2}|([zap])|([copas])?)$/).to_a
      if shorts.empty?
        announce _("what cards were that again?")
        return
      end
      full = shorts[0]
      short = shorts[1] || shorts[2] || shorts[3]
      card = p.has_card?(short) 
    else
      # new = > 1  |  2  |  3
      card = p.cards[card.to_i - 1]
    end
    card ? card : nil
  end

  def play_card(source, cards=nil, cover=false)
    if @called_truco 
      unless @accept_truco
        announce _("Voce deve aceitar ou nao o truco! Valor da rodada: %{v}") % { 
          :v => @round_value
        }
        return
      end
    end
    return unless cards
    
    p = get_player(source)
    if cards = get_card(source, cards)    
      set_discard(p.cards.delete_one(cards))

      unless cover
        if @top_card.nil?

          @top_card = @discard
          @top_card_owner = p
          announce _("%{p} começa a mão com %{card}") % { 
            :p => p, 
            :card => @discard
          }

        elsif @discard > @top_card
          @top_card = @discard
          @top_card_owner = p
          announce _("%{p} chegou matando com %{card}!") % { 
            :p => p, 
            :card => @discard
          }

        elsif @top_card == @discard
          # TODO: call draw
            @hands << [@players.first, @players[1]]
            announce _("%{p} jogou %{card}..e empata a mão") % { 
              :p => p, 
              :card => @discard
            }

        else
          announce _("%{p} não deu conta com esse %{card}, a maior carta é %{t}") % { 
            :p => p, 
            :card => @discard,
            :t => @top_card
          }  

        end
      end
      
      @turns += 1

      if @turns == @players.count  
        if @hands.length == 2 || @hands[0] == @top_card_owner 
          next_turn(:round)
        else
          next_turn(:hand)
        end
      else
        next_turn
      end
    else
      announce _("você não tem essa carta...")
    end
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  TRUCO
  # 
  def go_truco(source, ok)
    if @called_truco
      p = get_player(source)

      if @called_truco == p
        announce _("Seu oponente deve fazer isso...")
      else
        if ok
          announce _("%{p} aceitou truco...") % { :p => p }    
          @accept_truco = true
        else
          announce _("%{p} fugiu da parada...") % { :p => p }
          @accept_truco = false     
          next_turn(:round)
        end
      end
    end
  end
  
  def name_value(v)
    case v
    when 2..8
      "MEIIIIPAU!"
    when 9..11
      "NOOOOOOOOOVE!"
    else
      "PARTIDAAAAAAA!!!"
    end
  end
  
  def value_increase
    @round_value == @round_value_default ? @round_value += 2 : @round_value += 3
    announce _("Essa rodada foi pra %{v}" % { :v => @round_value} )
  end

  def truco!(source)
    p = get_player(source)
    if @called_truco
      if @called_truco == p
        announce _("%{p}, você acabou de pedir truco, ô animal!" % { :p => p })
        return
      end
      announce _("%{p} Pediu: %{name} LADRÃO!!!"% { 
        :p => p,
        :name => name_value(@round_value)
         })

    else
      announce _("%{p} Pediu: TRUUUUUUUUUUUCO LADRÃO!!!"% { :p => p })

    end
    value_increase
    @accept_truco = false     
    @called_truco = p
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  SHOW STUFF
  #
  def show_time
    if @start_time
      announce _("This %{truco} game has been going on for %{time}") % {
        :truco => TRUCO,
        :time => elapsed_time
      }
    else
      announce _("The game hasn't started yet")
    end
  end

  def show_order
    announce _("%{truco} jogando: %{players}") % {
      :truco => TRUCO, :players => players.join(' ')
    }
  end

  def show_turn(opts={})
    cards = true
    cards = opts[:cards] if opts.key?(:cards)
    player = @players.first
    announce _("é a vez de %{player}") % { :player => player }
    show_user_cards(player) if cards
  end

  def has_turn?(source)
    @start_time && (@players.first.user == source)
  end

  def is_next?(source)
    @start_time && (@players[1].user == source)
  end

  def show_discard
    announce _("Current discard: %{card} %{c}") % { :card => @discard,
      :c => (SPECIALS === @discard) ? TrucoGame.irc_naipe_bg(@naipe) + " #{@naipe} " : nil
    }
    show_picker
  end

  def show_user_cards(player)
    p = Player === player ? player : get_player(player)
    return unless p
    notify p, _('Your cards: %{cards}') % {
      :cards => p.cards.join(' ')
    }
  end

  def show_all_cards(u=nil)
    show_user_cards(u) if u
  end

  def deal(player, num=1)
    picked = []
    num.times do
      picked << @stock.delete_one
    end
    picked.sort!
    #notify player, _("Você recebeu %{picked}") % { :picked => picked.join(' ') }
    player.cards += picked
    player.cards.sort!
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  PLAYER MANAGEMENT
  #
  def add_player(user)
    if p = get_player(user)
      announce _("you're already in the game, %{p}") % {
        :p => p
      }
      return
    end
    @dropouts.each do |dp|
      if dp.user == user
        announce _("you dropped from the game, %{p}, you can't get back in") % {
          :p => dp
        }
        return
      end
    end

    if @players.length > 6
      announce _("maximo de 6 jogaores, %{p}") % {
        :p => user
      }
      return
    end

    if @start_time
      announce _("Jogo já começou...espere o próximo, #{user}")
      return
    end

    p = Player.new(user)
    @players << p
    announce _("%{p} entrou no jogo %{truco}") % {
      :p => p, :truco => TRUCO
    }

    cards = 3
    deal(p, cards)
    return if @start_time
    if @join_timer
      @bot.timer.reschedule(@join_timer, 4) # 10s
    elsif @players.length > 1
      announce _("game will start in 5 seconds") # 20s
      @join_timer = @bot.timer.add_once(5) {
        start_game
      }
    end
  end

  def drop_player(nick)
    # A nick is passed because the original player might have left
    # the channel or IRC
    unless p = get_player(nick)
      announce _("%{p} isn't playing %{truco}") % {
        :p => p, :truco => TRUCO
      }
      return
    end
    announce _("%{p} gives up this game of %{truco}") % {
      :p => p, :truco => TRUCO
    }

    end_game
#    return
    @dropouts << @players.delete_one(p)
  end

  def replace_player(old, new)
    # The new user
    user = channel.get_user(new)
    if p = get_player(user)
      announce _("%{p} is already playing %{truco} here") % {
        :p => p, :truco => TRUCO
      }
      return
    end
    # We scan the player list of the player with the old nick, instead
    # of using get_player, in case of IRC drops etc
    @players.each do |p|
      if p.user.nick == old
        p.user = user
        announce _("%{p} takes %{b}%{old}%{b}'s place at %{truco}") % {
          :p => p, :b => Bold, :old => old, :truco => TRUCO
        }
        return
      end
    end
    announce _("%{b}%{old}%{b} isn't playing %{truco} here") % {
      :truco => TRUCO, :b => Bold, :old => old
    }
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #
  #  END GAME
  #
  def end_game(halted = false)
    runtime = @start_time ? Time.now -  @start_time : 0
    if halted
      if @start_time
        announce _("%{truco} game halted after %{time}") % {
          :time => elapsed_time,
          :truco => TRUCO
        }
      else
        announce _("%{truco} game halted before it could start") % {
          :truco => TRUCO
        }
      end
    else
      announce _("%{truco} game finished after %{time}! The winner is %{p}") % {
        :time => elapsed_time,
        :truco => TRUCO, :p => @players.first
      }
    end

    score = @players.inject(0) do |sum, p|
      sum += p.score #.inject(0) do |cs, c|
      #      cs += c.score
      #     end
      # end
      sum
    end

    closure = { :dropouts => @dropouts, :players => @players, :runtime => runtime }
    if not halted
      announce _("%{p} wins with %{b}%{score}%{b} points!") % {
        :p => @players.first, :score => score, :b => Bold
      }
      closure.merge!(:winner => @players.first, :score => score,
      :opponents => @players.length - 1)
    end

    @plugin.do_end_game(@channel, closure)
  end
end

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#  TRUCO
#
# A won game: store score and number of opponents, so we can calculate
# an average score per opponent (requested by Squiddhartha)
define_structure :TrucoGameWon, :score, :opponents
# For each player we store the number of games played, the number of
# games forfeited, and an trucoGameWon for each won game
define_structure :TrucoPlayerStats, :played, :forfeits, :won
class TrucoPlugin < Plugin
  attr :games
  def initialize
    super 
    @games = {}
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #  HELP
  #
  def help(plugin, topic="")
    case topic
    when 'commands'
      [
        _("'tru' para entrar"),
        _("'pl <carta>' pra jogar <carta>: ex.: 'pl 1' pra jogar a primeira carta, ou 'pl 3' pra jogar a última!"),
        _("'pc <carta>' pra jogar coberto"),
        _("'truco!' pra pedir truco"),        
        _("'ok' pra aceitar um truco"),        
        _("'no' pra fugir do truco"),        
        _("'ca' pra mostrar suas cartas"),
        _("'cd' pra mostrar o descarte atual"),
        _("'od' mostra a ordem de jogo"),
        _("'ti' mostra o tempo de jogo"),
        _("'tu' mostra de quem é a vez")
      ].join("; ")
    when 'rules'
      _("play all your cards, one at a time, by matching either the color or the value of the currently discarded card. ") +
      _("cards with special effects: Skip (next player skips a turn), Reverse (reverses the playing order), +2 (next player has to take 2 cards). ") +
      _("Wilds can be played on any card, and you must specify the color for the next card. ") +
      _("Wild +4 also forces the next player to take 4 cards, but it can only be played if you can't play a color card. ") +
      _("you can play another +2 or +4 card on a +2 card, and a +4 on a +4, forcing the first player who can't play one to pick the cumulative sum of all cards. ") +
      _("you can also play a Reverse on a +2 or +4, bouncing the effect back to the previous player (that now comes next). ")
    when /scor(?:e|ing)/, /points?/
      [
      _("The points won with a game of %{truco} are totalled from the cards remaining in the hands of the other players."),
      _("Each normal (not special) card is worth its face value (from 0 to 9 points)."),
      _("Each colored special card (+2, Reverse, Skip) is worth 20 points."),
      _("Each Wild and Wild +4 is worth 50 points.")
      ].join(" ") % { :truco => TrucoGame::TRUCO }
    when /cards?/
      [
      _("Existem 56 cards em um baralho de %{truco}."),
      _("É retirado do baralho as cartas 8, 9, 10, a ordem de valores fica: 3 2 A K J Q 7 6 5 4."),
      _("Existem também as quatro cartas especiais, Zap (4 ♣), Sete Copas ( 7 ♥), Espadilha (A ♠), Sete Ouro ( 7 ♦)"),
      _("Elas matam qualquer carta normal, na ordem que estão colocadas acima.")
      ].join(" ") % { :truco => TrucoGame::TRUCO }
    when 'admin'
      _("The game manager (the user that started the game) can execute the following commands to manage it: ") +
      [
      _("'truco drop <user>' to drop a user from the game (any user can drop itself using 'truco drop')"),
      _("'truco replace <old> [with] <new>' to replace a player with someone else (useful in case of disconnects)"),
      _("'truco transfer [to] <nick>' to transfer game ownership to someone else"),
      _("'truco end' to end the game before its natural completion")
      ].join("; ")
    else
      _("%{truco} game. !truco to start a game. see 'help truco rules' for the rules, 'help truco admin' for admin commands. In-game commands: %{cmds}.") % {
        :truco => TrucoGame::TRUCO,
        :cmds => help(plugin, 'commands')
      }
    end
  end
    
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  COMMANDS
  #
  def message(m)
    return unless @games.key?(m.channel)
    return unless m.plugin # skip messages such as: <someuser> botname,
    g = @games[m.channel]
    case m.plugin.intern
    when :tru # join game
      return if m.params
      g.add_player(m.source)
    when :truco!, :seis!, :doze!
      return if m.params or not g.start_time
        if g.has_turn?(m.source) || g.is_next?(m.source)
        g.truco!(m.source)
      else
        m.reply _("Acha bonito atrapalhar o jogo? Nao eh tua vez!")
      end
    when :pc # play covered
      return if m.params or not g.start_time
      if g.has_turn?(m.source)
        g.play_card(m.source, m.params.downcase, true)
      else
        m.reply _("It's not your turn")
      end
    when :pl # play card
      if g.has_turn?(m.source)
        g.play_card(m.source, m.params.downcase)
      else
        m.reply _("It's not your turn")
      end
    when :ok #  accept truco
      if g.called_truco
        if g.has_turn?(m.source) || g.is_next?(m.source)
          g.go_truco(m.source, true)
        else
          m.reply _("It's not your turn")
        end
      else
        m.reply _("Ninguem pediu truco...")
      end  
    when :no # deny truco
      if g.called_truco
        if g.has_turn?(m.source) || g.is_next?(m.source)
          g.go_truco(m.source, false)
        else
          m.reply _("It's not your turn")
        end
      else
        m.reply _("Ninguem pediu truco...")
      end          
    when :ca # show current cards
      return if m.params
      g.show_all_cards(m.source)
    when :cd # show current discard
      return if m.params or not g.start_time
      g.show_discard
    when :od # show playing order
      return if m.params
      g.show_order
    when :ti # show play time
      return if m.params
      g.show_time
    when :tu # show whose turn is it
      return if m.params
      if g.has_turn?(m.source)
        m.nickreply _("it's your turn, sleepyhead")
      else
        g.show_turn(:cards => false)
      end
    end
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #
  #
  #  GAME MANAGEMENT
  #
  def create_game(m, p)
    if @games.key?(m.channel)
      m.reply _("Já existe um %{truco} rodando aqui, quem começou foi %{who}. diga 'tru' pra entrar") % {
        :who => @games[m.channel].manager,
        :truco => TrucoGame::TRUCO
      }
      return
    end
    @games[m.channel] = TrucoGame.new(self, m.channel, m.source, p[:value], p[:end])
    @bot.auth.irc_to_botuser(m.source).set_temp_permission('truco::manage', true, m.channel)
    m.reply _("Ok, criado jogo de ♥ ♦ %{truco} ♠ ♣ no canal %{channel}, diga 'tru' pra entrar") % {
      :truco => TrucoGame::TRUCO,
      :channel => m.channel
    }
  end

  def transfer_ownership(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{truco} game running here") % { :truco => TrucoGame::TRUCO }
      return
    end
    g = @games[m.channel]
    old = g.manager
    new = m.channel.get_user(p[:nick])
    if new
      g.manager = new
      @bot.auth.irc_to_botuser(old).reset_temp_permission('truco::manage', m.channel)
      @bot.auth.irc_to_botuser(new).set_temp_permission('truco::manage', true, m.channel)
      m.reply _("%{truco} game ownership transferred from %{old} to %{nick}") % {
        :truco => TrucoGame::TRUCO, :old => old, :nick => p[:nick]
      }
    else
      m.reply _("who is this %{nick} you want me to transfer game ownership to?") % p
    end
  end

  def end_game(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{truco} game running here") % { :truco => TrucoGame::TRUCO }
      return
    end
    @games[m.channel].end_game(true)
  end

  def cleanup
    @games.each { |k, g| g.end_game(true) }
    super
  end
  
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #
  #
  #  CHANNEL
  #
  def chan_reg(channel)
    @registry.sub_registry(channel.downcase)
  end

  def chan_stats(channel)
    stats = chan_reg(channel).sub_registry('stats')
    class << stats
      def store(val)
        val.to_i
      end
      def restore(val)
        val.to_i
      end
    end
    stats.set_default(0)
    return stats
  end

  def chan_pstats(channel)
    pstats = chan_reg(channel).sub_registry('players')
    pstats.set_default(TrucoPlayerStats.new(0,0,[]))
    return pstats
  end

  def do_end_game(channel, closure)
    reg = chan_reg(channel)
    stats = chan_stats(channel)
    stats['played'] += 1
    stats['played_runtime'] += closure[:runtime]
    if closure[:winner]
      stats['finished'] += 1
      stats['finished_runtime'] += closure[:runtime]

      pstats = chan_pstats(channel)

      closure[:players].each do |pl|
        k = pl.user.downcase
        pls = pstats[k]
        pls.played += 1
        pstats[k] = pls
      end

      closure[:dropouts].each do |pl|
        k = pl.user.downcase
        pls = pstats[k]
        pls.played += 1
        pls.forfeits += 1
        pstats[k] = pls
      end

      winner = closure[:winner]
      won = TrucoGameWon.new(closure[:score], closure[:opponents])
      k = winner.user.downcase
      pls = pstats[k] # already marked played +1 above
      pls.won << won
      pstats[k] = pls
    end

    @bot.auth.irc_to_botuser(@games[channel].manager).reset_temp_permission('truco::manage', channel)
    @games.delete(channel)
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #
  #
  #  STATS
  #
  def do_chanstats(m, p)
    stats = chan_stats(m.channel)
    np = stats['played']
    nf = stats['finished']
    if np > 0
      str = _("%{nf} %{truco} games completed over %{np} games played. ") % {
        :np => np, :truco => TrucoGame::TRUCO, :nf => nf
      }
      cgt = stats['finished_runtime']
      tgt = stats['played_runtime']
      str << _("%{cgt} game time for completed games") % {
        :cgt => Utils.secs_to_string(cgt)
      }
      if np > nf
        str << _(" on %{tgt} total game time. ") % {
          :tgt => Utils.secs_to_string(tgt)
        }
      else
        str << ". "
      end
      str << _("%{avg} average game time for completed games") % {
        :avg => Utils.secs_to_string(cgt/nf)
      }
      str << _(", %{tavg} for all games") % {
        :tavg => Utils.secs_to_string(tgt/np)
        } if np > nf
        m.reply str
    else
      m.reply _("nobody has played %{truco} on %{chan} yet") % {
        :truco => TrucoGame::TRUCO, :chan => m.channel
      }
    end
  end

  def do_pstats(m, p)
    dnick = p[:nick] || m.source # display-nick, don't later case
    nick = dnick.downcase
    ps = chan_pstats(m.channel)[nick]
    if ps.played == 0
      m.reply _("%{nick} never played %{truco} here") % {
        :truco => TrucoGame::TRUCO, :nick => dnick
      }
      return
    end
    np = ps.played
    nf = ps.forfeits
    nw = ps.won.length
    score = ps.won.inject(0) { |sum, w| sum += w.score }
    str = _("%{nick} played %{np} %{truco} games here, ") % {
      :nick => dnick, :np => np, :truco => TrucoGame::TRUCO
    }
    str << _("forfeited %{nf} games, ") % { :nf => nf } if nf > 0
    str << _("won %{nw} games") % { :nw => nw}
    if nw > 0
      str << _(" with %{score} total points") % { :score => score }
      avg = ps.won.inject(0) { |sum, w| sum += w.score/w.opponents }/nw
      str << _(" and an average of %{avg} points per opponent") % { :avg => avg }
    end
    m.reply str
  end
  
  # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
  #
  #
  #  PLAYER MANAGEMENT
  #
  def replace_player(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{truco} game running here") % { :truco => TrucoGame::TRUCO }
      return
    end
    @games[m.channel].replace_player(p[:old], p[:new])
  end

  def drop_player(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{truco} game running here") % { :truco => TrucoGame::TRUCO }
      return
    end
    @games[m.channel].drop_player(p[:nick] || m.source.nick)
  end

  def print_stock(m, p)
    unless @games.key?(m.channel)
      m.reply _("There is no %{truco} game running here") % { :truco => TrucoGame::TRUCO }
      return
    end
    stock = @games[m.channel].stock
    m.reply(_("%{num} cards in stock: %{stock}") % {
      :num => stock.length,
      :stock => stock.join(' ')
      }, :split_at => /#{NormalText}\s*/)
  end

  def do_top(m, p)
    pstats = chan_pstats(m.channel)
    scores = []
    wins = []
    pstats.each do |k, v|
      wins << [v.won.length, k]
      scores << [v.won.inject(0) { |s, w| s+=w.score }, k]
    end

    if n = p[:scorenum]
      msg = _("%{truco} %{num} highest scores: ") % {
        :truco => TrucoGame::TRUCO, :num => p[:scorenum]
      }
      scores.sort! { |a1, a2| -(a1.first <=> a2.first) }
      scores = scores[0, n.to_i].compact
      i = 0
      if scores.length <= 5
        list = "\n" + scores.map { |a|
          i+=1
          _("%{i}. %{b}%{nick}%{b} with %{b}%{score}%{b} points") % {
            :i => i, :b => Bold, :nick => a.last, :score => a.first
          }
          }.join("\n")
      else
        list = scores.map { |a|
          i+=1
          _("%{i}. %{nick} ( %{score} )") % {
            :i => i, :nick => a.last, :score => a.first
          }
          }.join(" | ")
      end
    elsif n = p[:winnum]
      msg = _("%{truco} %{num} most wins: ") % {
        :truco => TrucoGame::TRUCO, :num => p[:winnum]
      }
      wins.sort! { |a1, a2| -(a1.first <=> a2.first) }
      wins = wins[0, n.to_i].compact
      i = 0
      if wins.length <= 5
        list = "\n" + wins.map { |a|
          i+=1
          _("%{i}. %{b}%{nick}%{b} with %{b}%{score}%{b} wins") % {
            :i => i, :b => Bold, :nick => a.last, :score => a.first
          }
          }.join("\n")
      else
        list = wins.map { |a|
          i+=1
          _("%{i}. %{nick} ( %{score} )") % {
            :i => i, :nick => a.last, :score => a.first
          }
          }.join(" | ")
        end
    else
      msg = _("uh, what kind of score list did you want, again?")
      list = _(" I can only show the top scores (with top) and the most wins (with topwin)")
    end
    m.reply msg + list, :max_lines => (msg+list).count("\n")+1
  end
end

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#  TRUCO < RBOT
#            
tp = TrucoPlugin.new
tp.map 'truco', :private => false, :action => :create_game
tp.map 'truco end', :private => false, :action => :end_game, :auth_path => 'manage'
tp.map 'truco drop', :private => false, :action => :drop_player, :auth_path => 'manage::drop::self!'
tp.map 'truco giveup', :private => false, :action => :drop_player, :auth_path => 'manage::drop::self!'
tp.map 'truco drop :nick', :private => false, :action => :drop_player, :auth_path => 'manage::drop::other!'
tp.map 'truco replace :old [with] :new', :private => false, :action => :replace_player, :auth_path => 'manage'
tp.map 'truco transfer [game [ownership]] [to] :nick', :private => false, :action => :transfer_ownership, :auth_path => 'manage'
tp.map 'truco stock', :private => false, :action => :print_stock
tp.map 'truco chanstats', :private => false, :action => :do_chanstats
tp.map 'truco stats [:nick]', :private => false, :action => :do_pstats
tp.map 'truco top :scorenum', :private => false, :action => :do_top, :defaults => { :scorenum => 5 }
tp.map 'truco topwin :winnum', :private => false, :action => :do_top, :defaults => { :winnum => 5 }
tp.default_auth('stock', false)
tp.default_auth('manage', false)
tp.default_auth('manage::drop::self', true)