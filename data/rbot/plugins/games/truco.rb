#
# :title: Truco Game Plugin for rbot
#
# Author:: Marcos Piccinini <nofxx>
#
# Copyright:: (C) 2008 Marcos Piccinini
#
# License:: GPL v2
#
# Truco: You start with 3 cards. The values are as shown in the table. 
# The one who wins two hands, wins a point.
#
# If the first one drawns, the next one must decide (the most valuable card wins)
# 
# You can play with 2 or 4 ppl.
#
class TrucoPlugin < Plugin

  def initialize
    super 
    @scoreboard = {}
   
  end
  
end


class Truco
  NAIPES = %w{Ouro Copas Espada Paus}
  #Values already in the weight order
  VALUES  = %w{4 5 6 7 K J Q A 2 3}
  CARDS = []
  NAIPES.each do |n| 
    VALUES.each do |v| 
      CARDS << [n,v]
    end
  end
  
  # #
  # SPECIAL CARDS
  ZAP       = CARDS[4, 'Paus']
  ESPADILHA = CARDS['A', 'Espada']
  SETECOPAS = CARDS[7, 'Copas']
  SETEOURO  = CARDS[7, 'Ouro']

  # #
  # CARD
  #
  class Card
    attr_accessor :naipe
    attr_accessor :value
    
    def initialize(naipe, value)
      raise unless NAIPES.include? naipe
      @naipe = color.dup
      raise unless VALUES.include? value
      @value = value.dup
    end
    
  end
  
  
  class Player
  end
  
  
  
end