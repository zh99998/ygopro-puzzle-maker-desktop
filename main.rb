#encoding: UTF-8
require 'sqlite3'
require 'yaml'
$config = {
    "extra" => {"x" => 59, "y" => 84},
    "graveyard" => {"x" => 601, "y" => 0},
    "removed" => {"x" => 660, "y" => 0},
    "deck" => {"x" => 601, "y" => 84},
    "field" => [
        {"x" => 59, "y" => 0}, #场地魔法
        {"x" => 143, "y" => 84}, {"x" => 237, "y" => 84}, {"x" => 331, "y" => 84}, {"x" => 425, "y" => 84}, {"x" => 519, "y" => 84}, #后场
        {"x" => 143, "y" => 0}, {"x" => 237, "y" => 0}, {"x" => 331, "y" => 0}, {"x" => 425, "y" => 0}, {"x" => 519, "y" => 0} #前场
    ],
    "hand" => {"x" => 0, "y" => 201, "space" => 8},
    "section" => {"width" => 716, "height" => 266},
    "player_field" => {"x" => 4, "y" => 325},
    "opponent_field" => {"x" => 4, "y" => 0},
    "card" => {"width" => 160, "height" => 230},
    "thumbnail" => {"width" => 54, "height" => 81},
    "tip" => {"x" => 142, "y" => 285},
    "extname" => ".ydp"
}

class Card
  attr_accessor :number, :position, :player, :zone, :index, :x, :y, :shoes_image, :shoes_thumbnail
  DB = SQLite3::Database.new "cards.cdb"
  DB.results_as_hash = true
  @@all = []

  def initialize(player, zone, index)
    @player = player
    if zone.is_a? Integer
      @zone = zone
      pos = $config["field"][zone]
    else
      @zone = zone.to_sym
      pos = $config[zone.to_s]
      if @zone == :hand
        pos["x"] += index * ($config["thumbnail"]["width"]+$config["hand"]["space"])
      end
    end
    @position = :attack
    @index = index
    field_pos = player ? $config["player_field"] : $config["opponent_field"]
    @x = field_pos["x"] + (player ? pos["x"] : $config["section"]["width"] - pos["x"] - $config["thumbnail"]["width"])
    @y = field_pos["y"] + (player ? pos["y"] : $config["section"]["height"] - pos["y"] - $config["thumbnail"]["height"])

    @@all << self
  end

  def name=(name)
    #@number = nil
    DB.execute "select * from datas, texts where name = '#{name}' and texts.id = datas.id" do |row|
      #@name = row["name"]
      @number = row["id"].to_i
      @xyz = row["type"].to_i == 8388641
      @shoes_image.path = image if @shoes_image
      @shoes_thumbnail.path = thumbnail if @shoes_thumbnail
      Card.save
    end
  end

  def position=(position)
    return if @position == position
    @position = position
    Card.save
  end

  def overlapping?
    @xyz or [:deck, :graveyard, :removed, :extra, :hand].include? zone
  end

  def image
    if !@number
      "images/new.jpg"
    elsif @position == :set
      "textures/cover.jpg"
    elsif File.file? "pics/#{@number}.jpg"
      "pics/#{@number}.jpg"
    else
      "textures/unknown.jpg"
    end
  end

  def thumbnail
    if !@number or @position == :set or !File.file? "pics/thumbnail/#{@number}.jpg"
      image
    else
      "pics/thumbnail/#{@number}.jpg"
    end
  end

  def ygopro_zone
    "LOCATION_" +
        case @zone
          when 6..10
            "MZONE"
          when 0..5
            "SZONE"
          when :graveyard
            "GRAVE"
          else
            @zone.to_s.upcase
        end
  end

  def ygopro_index
    case @zone
      when 6..10
        @zone - 6
      when 1..5
        @zone - 1
      when 0
        5
      else
        @index
    end
  end

  def ygopro_position
    case @position
      when :attack
        "POS_FACEUP_ATTACK"
      when :defense
        "POS_FACEUP_DEFENSE"
      when :set
        "POS_FACEDOWN_DEFENSE"
    end
  end

  def to_hash
    return unless @number
    {"number" => @number, "player" => @player, "zone" => @zone, "index" => @index, "position" => @position.to_s}
  end

  def self.all_by_zone(player, zone)
    result = []
    @@all.each do |card|
      if card.player == player and card.zone == zone
        result << card
        yield card if block_given?
      end
    end
    result
  end

  def self.save(name="Unnamed")
    cards = []
    @@all.each { |card| cards << card if card.number }
    card_hashs = cards.collect { |card| card.to_hash }
    open(name+$config["extname"], 'w') { |f| f.write ({"name" => name, "player_lp" => $player1_lp, "opponent_lp" => $player2_lp, "cards" => card_hashs}.to_yaml) }
    open(name+'.lua', 'w') do |f|
      f.puts '--created by ygopro puzzle maker'
      f.puts "Debug.SetPlayerInfo(0,#{$player1_lp},1,0)"
      f.puts "Debug.SetPlayerInfo(1,#{$player2_lp},1,0)"
      f.puts "Debug.SetAIName('#{name}')"
      f.puts '--Debug.SetDuelInfo(DUEL_ATTACK_FIRST_TURN+DUEL_SIMPLE_AI)'
      f.puts 'Debug.ReloadFieldBegin(true)'
      cards.each do |card|
        f.puts "Debug.AddCard(#{card.number},#{card.player ? 0 : 1},#{card.player ? 0 : 1},#{card.ygopro_zone},#{card.ygopro_index},#{card.ygopro_position})"
      end
      f.puts 'Debug.ReloadFieldEnd()'
      f.puts 'Debug.ShowHint("在这个回合取得胜利！")'
    end
  end
end

def create_card(player, zone, index)
  result = Card.new(player, zone, index)
  stack(left: result.x, top: result.y, width: $config["thumbnail"]["width"], height: $config["thumbnail"]["height"]) do
    result.shoes_thumbnail = image result.thumbnail, width: $config["thumbnail"]["width"], height: $config["thumbnail"]["height"]
    hover do
      @border.left = result.x - 1
      @border.top = result.y - 1
      @border.show
    end
    leave do
      @border.hide
    end
    click do |button|
      if button == 1
        dialog width: result.overlapping? ? 160*5 : 160, height: 230+10, title: result.zone.to_s, scroll: false do
          background 'images/cardselect_background.png'
          Card.all_by_zone result.player, result.zone do |card|
            s = stack width: $config["card"]["width"], height: $config["card"]["height"] do
              i = image card.image, width: $config["card"]["width"], height: $config["card"]["height"]
              t = edit_line(width: $config["card"]["width"]) do
                t.change do
                  card.name = t.text
                  if card.number
                    i.path = card.image
                    all = Card.all_by_zone(result.player, result.zone)
                    if all.all? { |card| card.number }
                      create_card true, result.zone, all.max_by { |card| card.index }.index.next
                    end
                  end
                end
              end
              hover do
                t.top = 0
              end
              leave do
                t.top = -50
              end
              click do |button|
                #raise button.inspect
              end
            end
          end
        end
      else
        case result.position
          when :attack
            if (6..10).include? result.zone
              result.position = :defense
              result.shoes_thumbnail.rotate -90
            else
              result.position = :set
            end
          when :defense
            result.position = :set
          when :set
            result.position = :attack
            if (6..10).include? result.zone
              result.shoes_thumbnail.rotate 90
            end
        end
        result.shoes_thumbnail.path = result.thumbnail
      end
    end
  end
  result
end

Shoes.app title: "YGOPRO Duel Puzzle Maker", width: 1024, height: 640, resizable: false do

  background 'images/background.jpg'
  p = para("左键点击编辑卡片 右键点击切换表示形式", family: "微软雅黑")
  p.left = $config["tip"]["x"]
  p.top = $config["tip"]["y"]
  t1 = edit_line(text: "8000") do
    t1.change do
      $player1_lp = t1.text.to_i
      Card.save
    end
  end
  t2 = edit_line(text: "8000") do
    t2.change do
      $player2_lp = t2.text.to_i
      Card.save
    end
  end
  $player1_lp = 8000
  $player2_lp = 8000
  @border = image 'images/cursor.png'
  @border.hide
  ([:extra, :graveyard, :removed, :deck, :hand] + (0..10).to_a).each { |zone| create_card(true, zone, 0); create_card(false, zone, 0) }
end
