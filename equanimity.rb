require 'rubygems'
require 'camping'
require 'date'

require 'active_record'

dbconfig = YAML.load(File.read('config/database.yml'))
ActiveRecord::Base.establish_connection dbconfig['production']


Camping.goes :Equanimity

module Equanimity::Controllers
  class Index < R '/'
    def get
      render :index
    end
  end

  class List
    def get
      @entries = Entry.find(:all)
      render :list
    end
  end

  class ChooseNewDay
    def get
      @day = Date.today
      render :choose_new_day
    end
    def post
      redirect EditDayNNN, @input['year'], @input['month'], @input['day']
    end
  end

  class EditDayNNN
    def get(y,m,d)
      @day= Date.civil(y.to_i,m.to_i,d.to_i)
      @entries = Entry.find(:all)
      render :edit_day
    end
    def post(y,m,d)
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
      @day = Date.today
      @entries = Entry.find(:all)
      render :edit_day
    end
  end
end

module Equanimity::Models

  class Entry < Base
  end

  class GetStarted < V 1.0
    def self.up
      create_table Entry.table_name do | t|
        t.date :date
        t.string :key
        t.float :value
      end
    end
    def self.down
      drop_table Entry.table_name
    end
  end
end


module Equanimity::Views
  def layout
    html do
      head do
        title "../|equanimity|\...?"
      end
      body do
        table  do
          tr do
            td :colspan => 2, :style => "background-color: #AA9" do
              h1 do
                a  "...(-:equanimity:-)...?" , :href => R(Index)
              end
            end
          end
          tr do
            td :width => '100px',:style => "background-color: #FFC; padding: 30px" do
              p { a "new entry for today", :href => R(NewDay)}
              p { a "new entry for when?", :href => R(ChooseNewDay) }
              p { a "list all days", :href => R(List) }
            end
            td :width => '700px',:style => "background-color: #DDC; padding: 30px" do
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
    h2 "here's all your days, yo."
    table
    tr do 
      th "_-'-.day.-'-_"
      @keys.each { |k| th k }  
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

def Equanimity.create
  Equanimity::Models.create_schema
end

