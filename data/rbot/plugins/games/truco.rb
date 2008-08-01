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
#
# If the first one drawns, the next one must decide (the most valuable card wins)
# 
# You can play with 2 or 4 ppl.
#
#
# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
# 
#   TrucoGame
#
class TrucoGame
  NAIPES = %w{Ouro Copas Espada Paus}
  #Values already in the weight order
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
  # true if the player picked a card (and can thus pass turn)
  # attr_reader :player_has_picked
  # # number of cards to be picked if the player can't play an appropriate card
  # attr_reader :picker

  # game start time
  attr :start_time

  # the IRC user that created the game
  attr_accessor :manager
  
  def TrucoGame.color_map(clr)
    case clr
      when 'Ouro' then :red
      when 'Copas' then :white
      when 'Espada' then :black
      when 'Paus' then :white
    end
  end

  def TrucoGame.irc_naipe_bg(clr)
    cor = case clr
    when 'Ouro' then :white
    when 'Copas' then :red
    when 'Espada' then :white
    when 'Paus' then :black
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
  
  def TrucoGame.simbolizar(na)
    case na
      when 'Copas' then "♥ "
      when 'Ouro' then "♦ "
      when 'Paus' then "♣ "
      when 'Espada' then "♠ "
    end
  end
  

  TRUCO = TrucoGame.colorify('TRUCO!', true)
  
  def initialize(plugin, channel, manager)
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
    @round = 1
    @round_value = 1
    @called_truco = nil
    @top_card = nil
    @score = []
    @start_time = nil
    @join_timer = nil
    @must_play = nil
    @manager = manager
  end
  
  
  # ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
  # 
  #   Card
  #
  class Card
    attr_reader :naipe
    attr_reader :value
    attr_reader :shortform
    attr_reader :to_s
    attr_reader :score
    
    def initialize(naipe, value)
      raise unless NAIPES.include? naipe
      @naipe = naipe.dup
      raise unless VALUES.include? value
      @value = value.dup
     # @symbol = SYMBOLS[naipe.to_s]
      # if NUMERICS.include? value
      #   @value = value
      #   @score = value
      # else
      #   @value = value.dup
      #   @score = 20
      # end
      #if @value == '+2'
      #  @shortform = (@color[0,1]+@value).downcase
      #else
        @shortform = (@naipe[0,1]+@value.to_s[0,1]).downcase
      #end

      @to_s = TrucoGame.irc_naipe_bg(@naipe) +
         Bold + ["|", @value, TrucoGame.simbolizar(@naipe), @naipe, '|'].join(' ') + NormalText
    end
    
    def <=>(other)
      cc = self.naipe <=> other.naipe
      if cc == 0
        return self.value.to_s <=> other.value.to_s
      else
        return cc
      end
    end
    include Comparable
  end
  
  # ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
  # 
  #   Player
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
      has = []
      @cards.each { |c|
        has << c if c.shortform == short
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
  
  class Team
    def initialize(players)
      @players = players
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

  def announce(msg, opts={})
    @bot.say channel, msg, opts
  end
  
  def notify(player, msg, opts={})
    @bot.notice player.user, msg, opts
  end

  def make_base_stock
    # #
    # SPECIAL CARDS    
    zap       = %w{4 Paus}
    setecopas = %w{7 Copas}
    espadilha = %w{A Espada}
    seteouro  = %w{7 Ouro}
    
    especiais = [zap, setecopas, espadilha, seteouro]
    # @base_stock.delete(zap)
    # @base_stock.delete(espadilha)
    # @base_stock.delete(setecopas)
    # @base_stock.delete(seteouro)
    # @base_stock = especiais.concat(@base_stock)
    # # #
    # ORDER

#    list.concat(CARDS)
 #   list
    
    @base_stock = NAIPES.inject([]) do |list, naip|
      VALUES.each do |v|
        list << Card.new(naip, v)
        #list << Card.new(naip, v) unless v == 0
      end
      list
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

  def start_game(num_players)
    debug "TRUCO----------------START---------------> game"
    @players.shuffle!
    show_order
    announce _("%{p} começa o jogo!! partida N %{n}") % {
      :p => @players.first,
      :n => @round
    }
    #card = @stock.shift
    #@picker = 0
    ##@special = false
    #set_discard(card)
    #show_discard
    #if @special
  #    do_special
    #end
    #next_turn
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
     # if Wild === card
     #   @naipe = nil
     # else
     #   @naipe = card.color.dup
     # end
     # if card.picker > 0
     #   @picker += card.picker
     #   @last_picker = @discard.picker
     # end
     # if card.special?
     #   @special = true
     # else
     #   @special = false
     # end
     @must_play = nil
   end

   def next_turn(opts={})
     @players << @players.shift
  #   @player_has_picked = false
     show_turn
   end
   
   def next_round()
     @round_value = 1
     show_turn
   end

   def can_play(card)
     # if play is forced, check against the only allowed cards
    # return false if @must_play and not @must_play.include?(card)

     # When a +something is online, you can only play a +something of same or
     # higher something, or a Reverse of the correct color, or a Reverse on
     # a Reverse
     # TODO make optional
     # if @picker > 0
     #   return true if card.picker >= @last_picker
     #   return true if card.value == 'Reverse' and (card.color == @color or @discard.value == card.value)
     #   return false
     # else
       # You can always play a Wild
       #return true if Wild === card
       # On a Wild, you must match the color
       # if Wild === @discard
       #   return card.color == @color
       # else
     #     # Otherwise, you can match either the value or the color
     #     return (card.value == @value) || (card.color == @color)
     #   end
     # end
     true
   end

   def play_card(source, cards)
     debug "Playing card #{cards}"
     p = get_player(source)
     #shorts = cards.gsub(/\s+/,'').match(/^(?:([ceop]\+?\d){1,2}|([ceop][rs])|(w(?:\+4)?)([ceop])?)$/).to_a
     shorts = cards.gsub(/\s+/,'').match(/^(?:([ceop]\+?\d){1,2}|([ceop][rs])|(w(?:\+4)?)([ceop])?)$/).to_a
     debug shorts.inspect
     if shorts.empty?
       announce _("what cards were that again?")
       return
     end
     full = shorts[0]
     short = shorts[1] || shorts[2] || shorts[3]
     jolly = shorts[3]
     jcolor = shorts[4]
     if jolly
       toplay = 1
     else
       toplay = (full == short) ? 1 : 2
     end
     debug [full, short, jolly, jcolor, toplay].inspect
     # r7r7 -> r7r7, r7, nil, nil
     # r7 -> r7, r7, nil, nil
     # w -> w, nil, w, nil
     # wg -> wg, nil, w, g
     if cards = p.has_card?(short)
       debug cards
       #unless can_play(cards.first)
      #   announce _("you can't play that card")
      #   return
       #end
       if cards.length >= toplay
         # if the played card is a W+4 not played during a stacking +x
         # TODO if A plays an illegal W+4, B plays a W+4, should the next
         # player be able to challenge A? For the time being we say no,
         # but I think he should, and in case A's move was illegal
         # game would have to go back, A would get the penalty and replay,
         # while if it was legal the challenger would get 50% more cards,
         # i.e. 12 cards (or more if the stacked +4 were more). This would
         # only be possible if the first W+4 was illegal, so it wouldn't
         # apply for a W+4 played on a +2 anyway.
         #
         # if @picker == 0 and Wild === cards.first and cards.first.value 
         #   # save the previous discard in case of challenge
         #   @last_discard = @discard.dup
         #   # save the color too, in case it was a Wild
         #   @last_color = @color.dup
         # else
         #   # mark the move as not challengeable
         #   @last_discard = nil
         #   @last_color = nil
         # end
         set_discard(p.cards.delete_one(cards.shift))
         if toplay > 1
           set_discard(p.cards.delete_one(cards.shift))
           announce _("%{p} plays %{card} twice!") % {
             :p => p,
             :card => @discard
           }
         else
           announce _("%{p} jogou %{card}") % { :p => p, :card => @discard }
           
         end
         # if p.cards.length == 1
         #   announce _("%{p} has %{truco}!") % {
         #     :p => p, :truco => TRUCO
         #   }
         if p.cards.length == 0
           next_round
           return
         end
         # show_picker
         #         if @color
         #           if @special
         #             do_special
         #           end
         #           next_turn
         #         elsif jcolor
         #           choose_color(p.user, jcolor)
         #         else
         #           announce _("%{p}, choose a color with: co r|b|g|y") % { :p => p }
         #         end
         # 
         p.score(@round_value)
         next_turn
       else
         announce _("you don't have two cards of that kind")
       end
     else
       announce _("you don't have that card")
     end
   end
   
   def pass(user)
     p = get_player(user)
     # if @picker > 0
     #   announce _("%{p} passes turn, and has to pick %{b}%{n}%{b} cards!") % {
     #     :p => p, :b => Bold, :n => @picker
     #   }
     #   deal(p, @picker)
     #   @picker = 0
     # else
       # if @player_has_picked
       #   announce _("%{p} passes turn") % { :p => p }
       # else
       #   announce _("you need to pick a card first")
       #   return
       # end
     # end
     next_turn
   end
   
   def truco!
     p = @players.first
     if @called_truco == p
       announce _("%{p}, você acabou de pedir truco, ô animal!" % { :p => p })
     else
       announce _("%{p} Pediu: TRUUUUUUUUUUUCO LADRÃO!!!"% { :p => p })
       @called_truco = p
       @round_value == 1 ? @round_value = 3 : @round_value *= 2
       announce _("Essa mão agora vale %{v}" % { :v => @round_value} )
     end
   end
   
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
     announce(@players.inject([]) { |list, p|
       list << [p, p.cards.length].join(': ')
     }.join(', '))
     if u
       show_user_cards(u)
     end
   end
   
   def deal(player, num=1)
     picked = []
     num.times do
       picked << @stock.delete_one
       # if @stock.length == 0
       #        announce _("Shuffling discarded cards")
       #        make_stock
       #        if @stock.length == 0
       #          announce _("No more cards!")
       #          end_game # FIXME nope!
       #        end
       #      end
     end
     picked.sort!
     notify player, _("Você recebeu %{picked}") % { :picked => picked.join(' ') }
     player.cards += picked
     player.cards.sort!
   end
   
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
     
     if @players.length > 4
       announce _("maximo de 4 jogaores, %{p}") % {
         :p => user
       }
       return
     end
     
     cards = 3
     if @start_time
       cards = (@players.inject(0) do |s, pl|
         s +=pl.cards.length
       end*1.0/@players.length).ceil
     end
     p = Player.new(user)
     @players << p
     announce _("%{p} entrou no jogo %{truco}") % {
       :p => p, :truco => TRUCO
     }
     
     deal(p, cards)
     return if @start_time
     if @join_timer
       @bot.timer.reschedule(@join_timer, 4) # 10s
     elsif @players.length > 1
       announce _("game will start in 5 seconds") # 20s
       @join_timer = @bot.timer.add_once(5) {
         if @players.length == 2
           start_game(:two)
         elsif @players.length == 4
           start_game(:four)
         end
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
     case @players.length
     when 2
       if p == @players.first
         next_turn
       end
       end_game
       return
     when 1
       end_game(true)
       return
     end
     debug @stock.length
     while p.cards.length > 0
       @stock.insert(rand(@stock.length), p.cards.shift)
     end
     debug @stock.length
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
     # if @picker > 0 and not halted
     #   p = @players[1]
     #   announce _("%{p} has to pick %{b}%{n}%{b} cards!") % {
     #     :p => p, :n => @picker, :b => Bold
     #   }
     #   deal(p, @picker)
     #   @picker = 0
     # end
     score = @players.inject(0) do |sum, p|
       if p.cards.length > 0
         announce _("%{p} still had %{cards}") % {
           :p => p, :cards => p.cards.join(' ')
         }
         sum += p.cards.inject(0) do |cs, c|
           cs += c.score
         end
       end
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


# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## 
# 
#   TrucoPlugin
#
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
  
  def help(plugin, topic="")
    case topic
    when 'commands'
      [
      _("'tru' para entrar"),
      _("'pl <carta>' pra jogar <carta>: ex.: 'pl 7o' pra jogar 7 de Ouro, ou 'pl zap' pra jogar o Zap!"),
      _("'pa' pra descartar no monte"),
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
  
  def message(m)
    return unless @games.key?(m.channel)
    return unless m.plugin # skip messages such as: <someuser> botname,
    g = @games[m.channel]
    case m.plugin.intern
    when :tru # join game
      return if m.params
      g.add_player(m.source)
    when :truco!
      return if m.params or not g.start_time
      if g.has_turn?(m.source)
        g.truco!
      else
        m.reply _("Acha bonito atrapalhar o jogo? Nao eh tua vez!")
      end
    when :seis!
      return if m.params or not g.start_time
      if g.has_turn?(m.source)
        g.truco!
      else
        m.reply _("Acha bonito atrapalhar o jogo? Nao eh tua vez!")
      end
    when :pa # pass turn
      return if m.params or not g.start_time
      if g.has_turn?(m.source)
        g.pass(m.source)
      else
        m.reply _("It's not your turn")
      end
    when :pl # play card
      if g.has_turn?(m.source)
        g.play_card(m.source, m.params.downcase)
      else
        m.reply _("It's not your turn")
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

  def create_game(m, p)
    if @games.key?(m.channel)
      m.reply _("Já existe um %{truco} rodando aqui, quem começou foi %{who}. diga 'tru' pra entrar") % {
        :who => @games[m.channel].manager,
        :truco => TrucoGame::TRUCO
      }
      return
    end
    @games[m.channel] = TrucoGame.new(self, m.channel, m.source)
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