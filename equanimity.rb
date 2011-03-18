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
  def get_current_user
    @current_user = Equanimity::Models::User.current_user(@state.session_key)
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
      redirect R(Index) unless get_current_user
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
      get_current_user
      @entries = @current_user.entries
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
      get_current_user
      @day = Date.today
      render :choose_new_day
    end
    def post
      redirect EditDayNNN, @input['year'], @input['month'], @input['day']
    end
  end

  class EditDayNNN
    def get(y,m,d)
      get_current_user
      @day= Date.civil(y.to_i,m.to_i,d.to_i)
      @entries = @current_user.entries
#      @entries = Entry.find(:all)
      render :edit_day
    end
    def post(y,m,d)
      get_current_user
      @day= Date.civil(y.to_i,m.to_i,d.to_i)

      # work through input see what we're gonna do

      @input.keys.each do |k|
        this_key, this_val = nil, nil
        if /key_/.match(k)
          this_key = k.sub(/key_/, '')
          this_val = @input[k]
        elsif k == 'new_key'
          this_key = @input['new_key']
          this_val = @input['new_value']
        end

        if this_val.to_s.length > 0
          if e = @current_user.entries.find_by_date_and_key(@day, this_key)
            e.value = this_val
            e.save
          else
            e = @current_user.entries.create(:date => @day, :key => this_key, :value => this_val)
          end
        else
          if e = @current_user.entries.find_by_date_and_key(@day, this_key)
            Entry.delete(e)
          end
        end
      end
      redirect EditDayNNN, y, m, d
    end
  end

  class NewDay
    def get
      get_current_user
      @day = Date.today
      @entries = @current_user.entries
      render :edit_day
    end
  end

  class ChangePassword
    def get
      if get_current_user
        render :change_password
      else
        redirect Index
      end
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
end

module Equanimity::Models
  class User < Base
    has_many :entries
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
      head { title "../|#{possessive}equanimity|\...?" }
      body do
        table  do
          tr do
            td :colspan => 2, :style => "background-color: #AA9" do
              h1 do
                a  "...(-:#{possessive}equanimity:-)...?" , :href => R(Index)
              end
            end
          end
          tr do
            td :width => '200px',:style => "background-color: #FFC; padding: 30px" do
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
            td :width => '700px',:style => "background-color: #DDC; padding: 30px" do
              if @state['message']
                div.message! @state.delete('message')
              end
              self << yield 
            end
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
    @keys = @entries.map { |e| e.key }.uniq.sort
    @days = @entries.map { |e| e.date }.uniq.sort
#    STDERR.print @days.inspect
    puts "days:"
    puts @days.inspect
    puts "that was days."
    @all_days = (@days.first .. @days.last).to_a
    
    @charts = {}
    @keys.each do |k|
      maxforkey = @entries.select { |e| e.key == k }.map { |e| e.value }.max
      maxforkey = 10.0 if maxforkey < 10.0
      data = @all_days.map { |d|
        entry_for_day = @entries.detect { |e| e.key == k and e.date == d }
        if entry_for_day
          entry_for_day.value
        else
          "_"
        end
      }
        i = 0
      url="https://chart.googleapis.com/chart?" +
        [ "cht=bvg",
          "chs=1000x200",
          "chd=t:"+data.join(","),
          "chds=0.0,#{maxforkey}",
          "chxt=y,x,x,x,x",
          "chxr=0,0.0,#{maxforkey},#{maxforkey / 10}",
          "chxl=1:|"+@all_days.map { |d| d.strftime("%a") }.join("|") +
          "|2:|"+@all_days.map { |d| d.strftime("%d") }.join("|") +
          "|3:|"+@all_days.map { |d| d.strftime("%b") }.join("|") +
          "|4:|"+@all_days.map { |d| d.strftime("%Y") }.join("|")
        ].join("&")
      @charts[k] = url
    end


    jstemplate = <<ENDJS
url="%s"
chart_img = document.getElementById("chart_img");
chart_img.src=url;
chart_img.style.display="inline";
ENDJS

    h2 "here's all your days, yo."
    img :id => "chart_img", :src=>"blah", :onclick => 'this.style.display="none"' ,:style => "display:none"

    table
    tr do 
      th "_-'-.day.-'-_"
      @keys.each { |k| 
        if @charts[k]
          th( :onclick => (jstemplate % [@charts[k]]), 
              :style => "background-color: #AA9") {
            k  
          }
        else
          th k
        end
      }  
    end
    @days.each do |d|
      tr do
        td d
        @keys.each do |k|
          td do
            e4k = @entries.detect { |e| e.date == d and  e.key == k } and e4k.value  # this works? wow.
          end
        end
        td do
          a "...edit", :href => R(EditDayNNN, d.year, d.month, d.day)
        end
      end
    end
  end

  def csv
    @keys = @entries.map { |e| e.key }.uniq.sort
    @days = @entries.map { |e| e.date }.uniq.sort
    @all_days = (@days.first .. @days.last).to_a
    
    csv = %Q("day")
    @keys.each { |k| 
      csv << %Q(,"#{k}")
    }  
    csv << "\n";
  
    @days.each do |d|
      csv << %Q("#{d}")
      @keys.each do |k|
        maybe_e4k = (e4k = @entries.detect { |e| e.date == d and  e.key == k } and e4k.value)
        csv << %Q(,"#{maybe_e4k}")
      end
      csv << "\n"
    end
    pre {
      csv
    }
    
  end

  def edit_day
    @keys = @entries.map { |e| e.key }.uniq.sort

    h2 "it's a new day, yo: #{@day}"
    form :action => R(EditDayNNN, @day.year, @day.month, @day.day), :method => :post, :name => 'oldattrs' do
      table do
        @keys.each do | k |
          key_name = "key_#{k}"
          entries_with_this_key = @entries.select { |e| e.key == k }
          existing_entry = entries_with_this_key.detect { |e| e.date == @day }
          current_value = if existing_entry; existing_entry.value; else; ''; end
          old_values = entries_with_this_key.map { |e| e.value }.uniq.sort
          tr do
            td k
            td { input :name => key_name, :value => current_value }
            old_values.each do | v |
              td v, :onclick => "document.forms['oldattrs'].elements['#{key_name}'].value='#{v}'" ,  :style => "background-color: lightblue"
            end
            td 'clear', :onclick => "document.forms['oldattrs'].elements['#{key_name}'].value=''" ,  :style => "background-color: pink"
          end
        end

        tr do
          td {input :name => 'new_key'}
          td {input :name => 'new_value'}
        end
      end
      input :type => 'submit', :value => 'gotcha.'
    end
  end
end

# def Equanimity.create
#   Equanimity::Models.create_schema
# end


