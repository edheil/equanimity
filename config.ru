use Rack::Static, :urls => ["/public"]

require 'equanimity'
run Equanimity
