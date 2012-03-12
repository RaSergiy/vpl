#!/usr/bin/ruby
require 'rexml/document'
include REXML


class Vpl # =========================================================

  VIDEODIR            = File.expand_path "~/video"
  MEDIADB             = File.expand_path '~/.vpl/media.xml'
  MENUFILE_ORIGINAL1  = File.expand_path '~/.mplayer/menu.conf'   # tried first
  MENUFILE_ORIGINAL2  =                  '/etc/mplayer/menu.conf'  # tried if first try failed
  MPLAYER_MENU        = File.expand_path '~/tmp/vpl.menu.conf'
  AWESOME_MENU        = File.expand_path '/etc/xdg/awesome/vpl.lua'
  VIDEOFILES          = /\.(mk[av]|vob|mpeg|mp[34gc]|og[gm]|avi|wav|wm[av]|mov|asf|yuv|ram?|aac|nuv|m4[av]|flac|au|m2v|mp4v|qt|rm(vb)?|flv)$/i
  VIDEOFILES_VLC      = /\.(asf|wmv)$/i
  INFOTAGS = ['Author', 'Title', 'Year', 'Country', 'Time', 'Codec', 'Info', 'Annotation', 'Url' ]


  def initialize ( )
    puts "\nvpl: video player wrapper\n"
    @db = MediaDB.new Vpl::MEDIADB
    parse_args
    @media.each do |media|
      if media.selectedfile==-1
        to = media.files.count-1
        st = 0
      else
        to = media.selectedfile
        st = media.selectedfile
      end
      st.upto(to) do |i| 
          media.selectedfile=i
          media.dump @list
          play media unless @list
      end
    end
  end

  def help ()                 # :nodoc:
    puts "
Usage: vpl <filename1> ... [filenameN] [options]
  Options:
    -h, --help           This help
        --player-auto    Automatically choose player by filetype [default]
        --player-mplayer Force use VLC player
        --player-vlc     Force use MPlayer
        --awesome        Generates AWESOME's Lua menu
        --list           Print file/s parts list
        --nostop         Not stop at the end of the part [default]
        --stop           Stop at the end of the part
        --part=<name>    Seek to part <name>
        --partend=<name> Seek to part <name> end"
    exit
  end

  def parse_args ( )
    @list, @seek, @partend, @stop, @info = false, false, false, false, false
    @player = 'auto'
    @media = Array.new
    @args  = Array.new

    ARGV.each do |arg|    # Arguments processing
      case 
      when ( arg=='--help' || arg=='-h' ) then help
      when arg=='--awesome'               then @db.gen_awesome_menu Vpl::AWESOME_MENU
      when arg=='--nostop'                then @stop=false
      when arg=='--stop'                  then @stop=true
      when arg=='--list'                  then @list=true
      when arg=='--player-vlc'            then @player='vlc'
      when arg=='--player-mplayer'        then @player='mplayer'
      when arg=='--player-auto'           then @player='auto'
      when arg=~/--part=(.*)$/            then @seek="#$1"
      when arg=~/--partend=(.*)$/         then @seek="#$1"; @partend=true
      else
        if arg =~ Vpl::VIDEOFILES
          if File.exists? arg then                      # == EXISTING FILE 
            if ( media = @db.which_file arg ).nil?         # ====
              warning "File #{arg} not found in the database"
              media = Media.new.from_file File.expand_path arg
            end
            @media << media
          elsif ( media = @db.which_id arg ).nil?            # == MEDIA ID

            if (path=MediaFile.new(arg).path).empty?
              warning "File #{arg} does not exist"
              @args << arg
            else
                if ( media = @db.which_file arg ).nil?    # ===
                  warning "File #{arg} not found in the database"
                  media = Media.new.from_file path
                end
                @media << media
              
            end
          else 
            @media << media
          end # File.exists?
        elsif ( media = @db.which_id arg ).nil? # =~ VIDEOFILES
          @args << arg
        else 
          @media << media
        end
      end # case else
    end   # |arg|
    help if @media.count==0
  end




  def play (media)
    args=Array.new @args
    file = media.file
    if @player=='auto'
      if ( media.file.path =~ Vpl::VIDEOFILES_VLC && @seek) then player='vlc' else player='mplayer' end
    else player=@player end

    if ( file.parts.count > 0 and @player=='mplayer' )
      args << '-menu' << '-menu-cfg' << Vpl::MPLAYER_MENU if file.gen_mplayer_menu
    end
    if @seek
      part = file.find_part @seek
      error "Part #{@seek} not found" if part.nil?
      puts ">> #{part.time} #{part.name} #{part.title}"

      error "Partend for zero diapason" if ( part.time.vt <= 0 && @partend )
      case player
      when 'vlc'     then args << '--start-time' << if @partend then part.time.vt.to_s else part.time.vf.to_s end
      when 'mplayer' then args << '-ss' << if @partend then part.time.t else part.time.f end
      end

      if ( @stop && !part.time.t.empty? )
        error "Endpos for zero diapason" if ( part.time.vd <= 0 or part.time.t.empty?  )
        case player 
          when 'vlc'     then args << '--stop-time' << part.time.vt.to_s
          when 'mplayer' then args << '-endpos' << part.time.d
        end
      end
    end
    args << '--play-and-exit' << '--config' << File.expand_path('~/.config/vlc/vlcrc.my') if player=='vlc'
    args << media.file.path
    puts ">> #{player} >> #{args.join ' '}\n\n"
    system player, *args
  end


end # Vpl -----------------------------------------------------------



class VTime # Time ==================================================

  attr_accessor :time, :f, :t, :d, :vf, :vt, :vd

  def initialize ( t='0' )
    set t
  end

  def set (t)
    self.time = t
    self.f    = fmt ( from t )
    self.vf   = time2sec self.f     # time from val
    unless to(t).empty?
      self.t    = fmt ( to t )
      self.vt   = time2sec self.t     # time to val
      self.vd   = self.vt - self.vf   # time diapason val
      self.d    = fmt ( self.vd.to_s )# time diapason
    else
      self.t, self.vd  = ''
      self.vt, self.vd = 0
    end

  end

  # format to hh:mm:ss[-hh:mm:ss]
  def to_s ( )
    self.f + ( if self.t.empty? then '' else "-#{self.t}" end)
  end

  # format to hh:mm:ss  
  def fmt ( t )       # :nodoc:
    "%02d:%02d:%02d" % [ (sec = time2sec(t))/ 3600, (sec / 60) % 60, sec % 60 ] 
  end

  def from ( time )       # :nodoc:
    time.sub(/-.*/,'')
  end

  def to ( time )         # :nodoc:
    if time.include? ('-') then time.sub(/.*-/,'') else '' end;
  end

  # hh:mm:ss -> sec
  def time2sec ( time )       # :nodoc:
    sec=q=0; time.split(':').reverse.each { |t| sec += t.to_i * ( q==0 ? q=1 : q*=60) }; sec
  end


end # VTime ---------------------------------------------------------






class MediaPart # ===================================================
  attr_accessor :time, :name, :title
  def initialize ( time, name='', title='' )
    self.time  = VTime.new time
    self.name  = name
    self.title = title
  end
  def to_s()
    "%s : %s%s" % [ self.time, self.name, if self.title.empty? then '' else " : #{self.title}" end ]
  end
end # Media Part ----------------------------------------------------


class MediaFile # ===================================================

  attr_accessor :name, :path, :parts

  def initialize(name)
    self.name=name
    self.parts=[]
    self.path = pathregex2realpath name
  end

  def pathregex2realpath(pathregex)
    cmd = "find #{Vpl::VIDEODIR}/ -name '*' | grep '#{pathregex}'"
    unless (files=`#{cmd}`).empty?
      ret = []
      files.chop.split("\n").each { |f| ret << f unless File.directory? f }
      if ret.count > 1 then 
        warning "MediaFile pathregex '#{pathregex}' equals to multiple files (first one will be used):  "
        ret.each { |f| puts "file: #{f}" }
        return ret[0]
      end
      if ret.count == 1 then return ret[0] end
    end
    return pathregex if File.exists? pathregex
    warning( "File #{pathregex} not found" )
    ''
  end

  def find_part ( name )
    parts.each { |part| return part if part.name == name }; nil
  end


  def gen_mplayer_menu ( )  # :nodoc:
    File.open(Vpl::MPLAYER_MENU, File::CREAT | File::TRUNC | File::RDWR, 0644) do |f|
      if File.exists? Vpl::MENUFILE_ORIGINAL1 then f.puts IO.readlines(Vpl::MENUFILE_ORIGINAL1)
        elsif File.exists? Vpl::MENUFILE_ORIGINAL2 then f.puts IO.readlines(Vpl::MENUFILE_ORIGINAL2) end
      f.puts '<cmdlist name="videomarks" title="video marks" ptr="*">'
      self.parts.each do |p|
        f.puts '<e name="%s %s" ok="seek %d"/>' % [ p.time, p.name, p.time.vf ]
      end
      f.puts '</cmdlist>'
    end; true
  rescue
    warning 'Menu creation failed.'; false
  end


end # Media File ----------------------------------------------------



class Media # =======================================================

  attr_accessor :files, :selectedfile, :id, :info
  
  def initialize ( selectedfile = -1 )
    init ( selectedfile )
  end

  def init ( selectedfile )
    self.files = []
    self.info = { }
    self.selectedfile = selectedfile
  end

  def file ( )
    return nil if selectedfile==-1 or files.count==0
    self.files[self.selectedfile]
  end

  def from_file ( path )
    self.init(0)
    self.info['Title'] = File.basename path
    self.files << (MediaFile.new File.expand_path path)
    self
  end

  def from_xml ( xmedia, selectedfile)
    self.init(selectedfile)
    self.id = xmedia.attributes['id']
    Vpl::INFOTAGS.each { |i| unless (inf=xmedia.elements[i.downcase]).nil? then self.info[i]=inf.text end }
    xmedia.elements.each 'file' do |xfile|
      file = MediaFile.new xfile.attributes['name']
      xfile.elements.each('p') {|p| file.parts << MediaPart.new(p.attributes['t'], p.attributes['n'], p.attributes['a'])}
      self.files << file
    end # |xfile|
    self
  end

  def dump ( dump_list=false )
    Vpl::INFOTAGS.each  { |inf| unless self.info[inf].nil? then puts "%-12s: %s" % [inf, (self.info[inf]) ] end }
    if dump_list
      file = self.file
      return false if file.nil?
      if file.parts.count==0
        warning 'File does not contain parts'
      else
        file.parts.each { |part| puts "-- #{part}" }
      end
    end
    true
  end
end # Media ---------------------------------------------------------


class MediaDB # =====================================================

  
  def initialize ( path )
    error "Media database #{path} doesn't exist" unless FileTest::exist? path
    @xdb = Document.new File.new ( path )
  rescue => ex
    error "XML Parse: #{ex.class} : #{ex.message}"
  end



  # Находит *media* по пути файла, устанавливает *:selectedfile*

  def which_file ( filepath )
    def ff1 (xroot, filepath) # :nodoc:
      xroot.elements.each('media') do |xmedia|
        index=0
        xmedia.elements.each('file') do |xfile| 
          if /#{xfile.attributes['name']}$/ =~ filepath then  return Media.new.from_xml(xmedia, index) end
          index+=1
        end # xfile
      end   # xmedia
      xroot.elements.each('section') { |newxroot| unless (ret=ff1 newxroot, filepath).nil? then return ret end }
      nil
    end
    return ff1 @xdb.root, File.expand_path(filepath)
  rescue => ex
    error "which_file: #{ex.class} : #{ex.message}"
  end


  # Находит *media* по id файла, устанавливает *:selectedfile*

  def which_id ( id )
    def ff2 (xroot,id)     # :nodoc:
      xroot.elements.each('media') do |xmedia|
        unless ( z = xmedia.attributes['id'] ).nil? then return Media.new.from_xml(xmedia,-1) if z==id end
      end     # |media|
      xroot.elements.each('section') { |newxroot| unless (ret=ff2 newxroot, id).nil? then return ret end }
      nil
    end
    return ff2 @xdb.root, id
  rescue => ex
    error "which_id: #{ex.class} : #{ex.message}"
  end


  # Generates Awesome's LUA menu
  def gen_awesome_menu ( path )
    def scr ( str )
      str.gsub(/"/, '\"')
    end
    def mediatitle ( media, file ) # :nodoc:
       title = scr (if (media.info['Title'].nil? or media.info['Title'].empty?) then File.basename(file.path) else media.info['Title'] end)
    end
    def ff9 (f, xroot, name) # :nodoc:
      i=0
      sections = []
      xroot.elements.each 'section' do |section|
        sections << sect = { :name=>("%s_%02d" % [ name, (i+=1) ] ), :title=>section.attributes['title'] }
        ff9 f, section, sect[:name]
      end
      f.puts "#{name} = {"
      sections.each { |section| f.puts '{ "%s", %s},' % [ scr(section[:title]), section[:name]] }
      mediastr = String.new
      j=0
      xroot.elements.each('media') do |xmedia|
        media = Media.new.from_xml xmedia, -1
        media.files.each do |mf|
          next if mf.path.empty?

            f.puts '  { "%s", {  ' % [ mediatitle(media,mf) ]
            f.puts '    { ">> INFO", "termix.sh vpl --list %s"},' % [ mf.path ]
            f.puts '    { ">> PLAY", "vpl %s"},' % [ mf.path ]
            mf.parts.each do |p|
              f.puts '    { "%s : %s", "vpl --part=%s %s" },' % [ p.name, scr(p.title), p.name, mf.path ]
            end
            f.puts "  } },"

        end # |file|
      end   # |media|

      f.puts mediastr
      f.puts "}\n"
    end

    puts "Generating awesome menu ..."
    File.open(path, File::CREAT | File::TRUNC | File::RDWR, 0644) do |f|
      f.puts '-- Autogenerated file. Do not edit'
      f.puts 'module ("vpl")'
      ff9 f, @xdb.root, 'mediafiles'
    end
    exit
  end

end


def error (msg='', retcode=1 )
  puts "**ERROR: #{msg}"
  exit retcode
end

def warning (msg='')
  puts "**WARNING: #{msg}"
end

Vpl.new

