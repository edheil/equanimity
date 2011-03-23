require 'rubygems'
require 'camping'
require 'date'
require 'active_record'
require 'camping/session'
require 'digest/sha1'

dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig['production']

Camping.goes :Equanimity

module Equanimity
  set :secret, "HEYO"
  include Camping::Session
end

module Equanimity::Helpers
  def get_current_user(args={})
    @current_user = Equanimity::Models::User.current_user(@state.session_key)
    if args[:or_goto]
      unless @current_user
        redirect R(args[:or_goto])
        throw :halt
      end
    else
      @current_user
    end
  end
  def message(text)
    @state['message'] = text
  end
end


module Equanimity::Controllers
  class Index < R '/'
    def get
      if get_current_user
        render :index
      else
        render :login
      end
    end
  end

  class List
    def get
      get_current_user :or_goto => Index
      unless @current_user
        if args[:with_message]
          message args[:with_message]
        end
        redirect R(Index)
        throw :halt
      end
      @scales = @current_user.scales
      @entries = @current_user.entries
      if @entries.length > 0
        render :list
      else
        message "you have no entries."
        redirect R(Index)
      end
    end
  end

  class Csv
    def get
      get_current_user :or_goto => Index
      @entries = @current_user.entries
      @scales = @current_user.scales
      if @entries.length > 0
        @raw = true
        render :csv
      else
        message "you have no entries."
        redirect R(Index)
      end
    end
  end

  class ChooseNewDay
    def get
      get_current_user :or_goto => Index
      @day = Date.today
      render :choose_new_day
    end
    def post
      redirect EditDayNNN, @input['year'], @input['month'], @input['day']
    end
  end

  class EditDayNNN
    def get(y,m,d)
      get_current_user :or_goto => Index
      @day= Date.civil(y.to_i,m.to_i,d.to_i)
      render :edit_day
    end
    def post(y,m,d)
      get_current_user :or_goto => Index
      @day= Date.civil(y.to_i,m.to_i,d.to_i)

      # work through input see what we're gonna do

      @input.keys.each do |k|
        if /scale_/.match(k)
          scale_id = (k.sub(/scale_/, '').to_i)
          scale = Scale.find(scale_id)
          if @input[k].length > 0
            if e = scale.entries.find_by_date(@day)
              e.value = @input[k].to_i
              e.save
            else
              puts "creating new entry."
              e = scale.entries.new(:date => @day,
                                    :value => @input[k].to_i)
              e.save
            end
          else # zero length
            if e = scale.entries.find_by_date(@day)
              Entry.delete(e)
            end
            if scale.entries.length == 0 # that was the last entry
              Scale.delete(scale)
            end
          end
        elsif k == 'new_scale' and @input['new_scale'].length > 0
          new_scale_name = @input['new_scale']
          new_scale_val = @input['new_value'].to_i
          new_scale_max = [new_scale_val, 10].max
          # better make one, quick!
          current_scales = @current_user.scales
          new_scale = @current_user.scales.new(:name => new_scale_name,
                                               :max => new_scale_max)
          new_scale.save
          # add entry
          e = new_scale.entries.new(:date => @day,
                                    :value => new_scale_val);
        end
      end
      redirect EditDayNNN, y, m, d
    end
  end

  class NewDay
    def get
      get_current_user :or_goto => Index
      @day = Date.today
      @entries = @current_user.entries
      render :edit_day
    end
  end

  class ChangePassword
    def get
      get_current_user :or_goto => Index
      render :change_password
    end
  end

  class Login
    def get
      if get_current_user
        redirect Index
      else
        render :login
      end
    end
  end

  class About
    def get
      render :about
    end
  end
  class NewUser
    def get
      if get_current_user
        redirect Index
      else
        render :new_user
      end
    end
  end

  class Account
    def post
      if @input['submit'] == 'Logout'
        if @user = User.current_user(@state.session_key)
          @user.get_logged_out
          message "Successfully logged out #{@user.name}"
        else
          message "You were never logged in, brah."
        end
      elsif @input['submit'] == 'Change Password'
        if @user = User.current_user(@state.session_key) 
          if @user.valid_pass?( @input.old_password )
            @user.set_pass( @input.new_password )
            @user.save
            message "Successfully changed password."
          else
            message "Old password incorrect."
          end
        else
          message 'You\'re not even logged in; how can you change a password?'
        end
        redirect R(Index)
      elsif @input['submit'] == 'Login'
        @user = User.find_by_name(@input.name)
        @user = nil unless @user.valid_pass?( @input.password )
        if @user
          @state.session_key = @user.get_logged_in
          message "Nicely logged in, #{@input.name}."
        else
          message "no dice logging in as #{@input.name}"
        end
      elsif @input['submit'] == 'New User'
        @user = User.new(:name => @input.name)
        @user.set_pass(@input.password)
        if @user.save
          @state.session_key = @user.get_logged_in
          message "welcome to the glories of userhood, #{@input.name}."
        else
          message "no luck chuck! #{ @user.errors }"
        end
      end
      redirect Index
    end
  end

  # STATIC CONTROLLER


  class Static < R '/public/(.+)'
    MIME_TYPES = {'.css' => 'text/css', '.js' => 'text/javascript', '.jpg' => 'image/jpeg'}
    PATH = File.expand_path(File.dirname(__FILE__))
    def get(path)
      @headers['Content-Type'] = MIME_TYPES[path[/\.\w+$/, 0]] || "text/plain"
      unless path.include? ".." # prevent directory traversal attacks
        @headers['X-Sendfile'] = "#{PATH}/public/#{path}"
      else
        @status = "403"
        "403 - Invalid path"
      end
    end
  end
end

module Equanimity::Models
  class User < Base
    has_many :entries, :through => :scales, :order => 'date'
    has_many :scales, :order => 'name'
    validates_uniqueness_of :name, :message => " has already been taken."
    def get_logged_in
      self.session_key = "key-#{rand(99999999999)}"
      save
      return self.session_key
    end
    def get_logged_out
      self.session_key = nil
      save
    end
    def valid_pass?(pass)
      #self.password == pass
      self.salted_pass == Digest::SHA1.hexdigest(self.salt + pass)
    end
    def set_pass(pass)
      self.salt = "#{rand(9999999999)}"
      self.salted_pass = Digest::SHA1.hexdigest(self.salt + pass)
      # self.save ?
    end
    def self.current_user(session_key)
      if session_key
        find_by_session_key(session_key)
      else
        nil
      end
    end
  end

  class Entry < Base
    belongs_to :user
    belongs_to :scale
  end
  class Scale < Base
    validates_uniqueness_of :name, :scope => :user_id
    belongs_to :user
    has_many :entries
  end
end


module Equanimity::Views
  def layout
    if @raw
      self << yield 
      return
    end
    possessive = ""
    if @current_user
      possessive = "#{@current_user.name}'s "
    end

    html do
      head { 
        title "../|#{possessive}equanimity|\...?"
        link :rel => 'stylesheet', :href => '/public/blueprint/screen.css',:type => "text/css", :media => "screen, projection"
        link :rel => 'stylesheet', :href => 'public/blueprint/print.css',:type => "text/css", :media => "print"
        text "<!--[if lt IE 8]>"
        link :rel => 'stylesheet', :href => 'public/blueprint/ie.css',:type => "text/css", :media => "screen, projection"
        text "<![endif]-->"
      }
      body do
        div :class => "container" do
          div :class => "column span-24 last" do
            h1 do
              a  "...(-:#{possessive}equanimity:-)...?" , :href => R(Index)
            end
          end
          div :class => "column span-4" do
            div { a "about", :href => R(About) }
            if @current_user
              div { a "new entry for today", :href => R(NewDay)}
              div { a "new entry for when?", :href => R(ChooseNewDay) }
              div { a "list all days", :href => R(List) }
              div { a "csv days", :href => R(Csv) }
              div { a "change password", :href => R(ChangePassword) }
            else
              div { a "login", :href => R(Login) }
              div { a "new user", :href => R(NewUser) }
            end
            div do
              form :action => R(Account), :method => :post do
                if @current_user
                  input(:type => :submit, :name => :submit, :value => "Logout")
                end
              end
            end
          end
          div :class => "column span-20 last" do
            if @state['message']
              div.message! @state.delete('message')
            end
            self << yield 
          end
        end
      end
    end
  end

  def about
    text "blah blah blah about this app blah blah"
  end

  def index
    h2 "here's the index, yo"
  end

  def login
    h2 "Login"
    form :action => R(Account), :method => :post do
      div do
        text "name: "
        input(:type => :text, :name => :name)
      end
      div do
        text "password: "
        input(:type => :password, :name => :password)
      end
      input(:type => :submit, :name => :submit, :value => "Login")
    end
  end

  def new_user
    h2 "New User"
    form :action => R(Account), :method => :post do
      div do
        text "name: "
        input(:type => :text, :name => :name)
      end
      div do
        text "password: "
        input(:type => :password, :name => :password)
      end
      input(:type => :submit, :name => :submit, :value => "New User")
    end
  end

  def change_password
    form :action => R(Account), :method => :post do
      div do
        div do
          text "old password: "
          input(:type => :password, :name => :old_password)
        end
        div do
          text "new password: "
          input(:type => :password, :name => :new_password)
        end
        input(:type => :submit, :name => :submit, :value => "Change Password")
      end
    end
  end

  def choose_new_day
    h2 "what day do you want to enter?"
    form :action => R(ChooseNewDay), :method => :post do
      table do
        tr { td "year:"; td {input :name => "year", :value => @day.year }}
        tr { td "month:"; td {input :name => "month", :value => @day.month }}
        tr { td "day:"; td{input :name => "day", :value => @day.day }}
      end
      p { input :type => 'submit', :value => 'take me there' }
    end
  end
 


  def list

    # TODO:
    @days = @entries.map { |e| e.date }.uniq
    @all_days = (@days.first .. @days.last).to_a
    @scales.each do |s|
      k = s.name
      maxforkey = s.max
      data = @all_days.map { |d|
        entry_for_day = @entries.detect { |e| e.scale_id == s.id and e.date == d }
        if entry_for_day
          entry_for_day.value
        else
          "_"
        end
      }
    end

    table
    tr do 
      th "_-'-.day.-'-_"
      @scales.each { |s| th( :style => "background-color: #AA9") { s.name } }  
    end
    @days.each do |d|
      tr do
        td d
        @scales.each do |s|
          td do
            e4k = @entries.detect { |e| e.date == d and  e.scale == s } and e4k.value  # this works? wow.
          end
        end
        td do
          a "...edit", :href => R(EditDayNNN, d.year, d.month, d.day)
        end
      end
    end
  end

  def csv
    @days = @entries.map { |e| e.date }.uniq
    @all_days = (@days.first .. @days.last).to_a
    
    csv = %Q("day")
    @scales.each { |s| 
      csv << %Q(,"#{s.name}")
    }  
    csv << "\n";
  
    @days.each do |d|
      csv << %Q("#{d}")
      @scales.each do |s|
        maybe_e4k = (e4k = @entries.detect { |e| e.date == d and  e.scale == s } and e4k.value)
        csv << %Q(,"#{maybe_e4k}")
      end
      csv << "\n"
    end
    pre {
      csv
    }
    
  end

  def edit_day

    h2 "it's a new day, yo: #{@day}"
    form :action => R(EditDayNNN, @day.year, @day.month, @day.day), :method => :post, :name => 'oldattrs' do
      table do
        @current_user.scales.each do | s |
          scale_input_name = "scale_#{s.id}"
          entries_with_this_scale = s.entries
          existing_entry = entries_with_this_scale.detect { |e| e.date == @day }
          current_value = if existing_entry; existing_entry.value; else; ''; end
          old_values = entries_with_this_scale.map { |e| e.value }.uniq.sort
          tr do
            td s.name
            td { input :name => scale_input_name, :value => current_value }
            old_values.each do | v |
              td v, :onclick => "document.forms['oldattrs'].elements['#{scale_input_name}'].value='#{v}'" ,  :style => "background-color: lightblue"
            end
            td 'clear', :onclick => "document.forms['oldattrs'].elements['#{scale_input_name}'].value=''" ,  :style => "background-color: pink"
          end
        end

        tr do
          td {input :name => 'new_scale'}
          td {input :name => 'new_value'}
        end
      end
      input :type => 'submit', :value => 'gotcha.'
    end
  end
end

# DATABASE SCHEMA

# using proper migrations was cramping my dev flow, so I
# just managed my db manually.  Here's the final schema --
# for purposes of heroku deployment, you want this to be
# in a database in the path "db/development_sqlite3"
# and then you want to push it to heroku with heroku db:push
#
# CREATE TABLE `equanimity_entries` (`id` integer PRIMARY KEY AUTOINCREMENT, `date` date, scale_id integer, `value` integer);
# CREATE TABLE equanimity_scales (`id` integer PRIMARY KEY AUTOINCREMENT, `name` varchar(255), `max` integer, `user_id` integer);
# CREATE TABLE `equanimity_schema_infos` (`id` integer PRIMARY KEY AUTOINCREMENT, `version` double precision);
# CREATE TABLE `equanimity_users` (`id` integer PRIMARY KEY AUTOINCREMENT, `name` text, `session_key` text, `salted_pass` text, `salt` text);
