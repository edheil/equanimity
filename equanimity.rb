require 'rubygems'
require 'camping'
require 'date'
require 'active_record'
require 'camping/session'

dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig['production']

Camping.goes :Equanimity

module Equanimity
  set :secret, "HEYO"
  include Camping::Session
end

module Equanimity::Helpers
  def message(text)
    @state['message'] = text
  end
  # def requires_login!
  #   unless @current_user = User.find_by_valid_session_key(@state.session_key)
  #     redirect Index
  #     throw :halt
  #   end
  # end
end


module Equanimity::Controllers
  class Index < R '/'
    def get
    @current_user = User.current_user(@state.session_key)
      render :index
    end
  end

  class List
    def get
    @current_user = User.current_user(@state.session_key)
      @entries = Entry.find(:all)
      render :list
    end
  end

  class Csv
    def get
    @current_user = User.current_user(@state.session_key)
      @entries = Entry.find(:all)
      render :csv
    end
  end

  class ChooseNewDay
    def get
    @current_user = User.current_user(@state.session_key)
      @day = Date.today
      render :choose_new_day
    end
    def post
      redirect EditDayNNN, @input['year'], @input['month'], @input['day']
    end
  end

  class EditDayNNN
    def get(y,m,d)
    @current_user = User.current_user(@state.session_key)
      @day= Date.civil(y.to_i,m.to_i,d.to_i)
      @entries = Entry.find(:all)
      render :edit_day
    end
    def post(y,m,d)
    @current_user = User.current_user(@state.session_key)
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
          if e = Entry.find_by_date_and_key(@day, this_key)
            e.value = this_val
            e.save
          else
            e = Entry.create(:date => @day, :key => this_key, :value => this_val)
          end
        else
          if e = Entry.find_by_date_and_key(@day, this_key)
            Entry.delete(e)
          end
        end
      end
      redirect EditDayNNN, y, m, d
    end
  end

  class NewDay
    def get
    @current_user = User.current_user(@state.session_key)
      @day = Date.today
      @entries = Entry.find(:all)
      render :edit_day
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
      elsif @input['submit'] == 'Login'
        @user = User.find_by_name_and_password(@input.name, @input.password)
        if @user
          @state.session_key = @user.get_logged_in
          message "Nicely logged in, #{@input.name}."
        else
          message "no dice logging in as #{@input.name}"
        end
      elsif @input['submit'] == 'New User'
        @user = User.new(:name => @input.name, 
                         :password => @input.password)
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
    validates_uniqueness_of :name, :message => " has already been taken."
    def get_logged_in
      self.session_key = "#{rand(99999999999)}"
      save
      return self.session_key
    end
    def get_logged_out
      self.session_key = nil
      save
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
  end

  # class GetStarted < V 1.0
  #   def self.up
  #     create_table Entry.table_name do | t|
  #       t.date :date
  #       t.string :key
  #       t.float :value
  #     end
  #   end
  #   def self.down
  #     drop_table Entry.table_name
  #   end
  # end
  # class Continue < V 3.0
  #   def self.up
  #     drop_table User.table_name
  #     create_table User.table_name do |t|
  #       t.string :name
  #       t.string :password
  #       t.string :session_key
  #     end
  #   end
  #   def self.down
  #     drop_table User.table_name
  #   end
  # end
end


module Equanimity::Views
  def layout
    possessive = ""
    if @current_user
      possessive = "#{@current_user.name}'s "
    end
    html do
      head do
        title "../|#{possessive}equanimity|\...?"
      end
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
            td :width => '100px',:style => "background-color: #FFC; padding: 30px" do
              p { a "new entry for today", :href => R(NewDay)}
              p { a "new entry for when?", :href => R(ChooseNewDay) }
              p { a "list all days", :href => R(List) }
              p { a "csv days", :href => R(Csv) }

    div do
      form :action => R(Account), :method => :post do
        if @current_user
          p "current user is #{current_user.name}"
          input(:type => :submit, :name => :submit, :value => "Logout")
        else
          p "you are not currently logged in."
          div do
            text "name: "
            input(:type => :text, :name => :name)
          end
          div do
            text "password: "
            input(:type => :password, :name => :password)
          end
          input(:type => :submit, :name => :submit, :value => "Login")
          input(:type => :submit, :name => :submit, :value => "New User")
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

  def index
    h2 "here's the index, yo"
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

    @all_days = (@days.first .. @days.last).to_a
    
    @charts = {}
    @keys.each do |k|
      maxforkey = @entries.select { |e| e.key == k }.map { |e| e.value }.max
      maxforkey = 10.0 if maxforkey < 10.0
      data = @all_days.map { |d|
        entry_for_day = @entries.find { |e| e.key == k and e.date == d }
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
            e4k = @entries.find { |e| e.date == d and  e.key == k } and e4k.value  # this works? wow.
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
        maybe_e4k = (e4k = @entries.find { |e| e.date == d and  e.key == k } and e4k.value)
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

