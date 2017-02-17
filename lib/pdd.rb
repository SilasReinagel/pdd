# encoding: utf-8
#
# Copyright (c) 2014-2017 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'pdd/sources'
require 'pdd/version'
require 'pdd/rule/estimates'
require 'pdd/rule/text'
require 'pdd/rule/duplicates'
require 'pdd/rule/roles'
require 'nokogiri'
require 'logger'
require 'time'

# PDD main module.
# Author:: Yegor Bugayenko (yegor@teamed.io)
# Copyright:: Copyright (c) 2014-2017 Yegor Bugayenko
# License:: MIT
module PDD
  # If it breaks.
  class Error < StandardError
  end

  # If it violates XSD schema.
  class SchemaError < Error
  end

  RULES = {
    'min-estimate' => PDD::Rule::Estimate::Min,
    'max-estimate' => PDD::Rule::Estimate::Max,
    'min-words' => PDD::Rule::Text::MinWords,
    'max-duplicates' => PDD::Rule::MaxDuplicates,
    'available-roles' => PDD::Rule::Roles::Available
  }.freeze

  # Get logger.
  def self.log
    unless @logger
      @logger = Logger.new(STDOUT)
      @logger.formatter = proc { |severity, _, _, msg|
        "#{severity}: #{msg.dump}\n"
      }
      @logger.level = Logger::ERROR
    end
    @logger
  end

  class << self
    attr_writer :logger
  end

  # Code base abstraction
  class Base
    # Ctor.
    # +opts+:: Options
    def initialize(opts)
      @opts = opts
      PDD.log.level = Logger::INFO if @opts[:verbose]
      PDD.log.level = Logger::ERROR if @opts[:quiet]
      PDD.log.info "my version is #{PDD::VERSION}"
      PDD.log.info "Ruby version is #{RUBY_VERSION} at #{RUBY_PLATFORM}"
    end

    # Generate XML.
    def xml
      dir = @opts[:source] ? @opts[:source] : Dir.pwd
      PDD.log.info "reading #{dir}"
      sources = Sources.new(dir)
      @opts[:exclude].each do |p|
        sources = sources.exclude(p)
        PDD.log.info "excluding #{p}"
      end unless @opts[:exclude].nil?
      sanitize(
        rules(
          Nokogiri::XML::Builder.new do |xml|
            xml << "<?xml-stylesheet type='text/xsl' href='#{xsl}'?>"
            xml.puzzles(attrs) do
              sources.fetch.each do |source|
                source.puzzles.each do |puzzle|
                  PDD.log.info "puzzle #{puzzle.props[:id]} " \
                    "#{puzzle.props[:estimate]}/#{puzzle.props[:role]}" \
                    " at #{puzzle.props[:file]}"
                  render puzzle, xml
                end
              end
            end
          end.to_xml
        )
      )
    end

    private

    def attrs
      {
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:noNamespaceSchemaLocation' => "#{host('xsd')}/#{PDD::VERSION}.xsd",
        'version' => PDD::VERSION,
        'date' => Time.now.utc.iso8601
      }
    end

    def host(suffix)
      "http://pdd-#{suffix}.teamed.io"
    end

    def xsl
      "#{host('xsl')}/#{PDD::VERSION}.xsl"
    end

    def render(puzzle, xml)
      props = puzzle.props
      xml.puzzle do
        props.map do |k, v|
          xml.send(:"#{k}", v)
        end
      end
    end

    def rules(xml)
      doc = Nokogiri::XML(xml)
      total = 0
      (@opts[:rule] || []).push('max-duplicates:1').map do |r|
        name, value = r.split(':')
        rule = RULES[name]
        raise "rule '#{name}' doesn't exist" if rule.nil?
        rule.new(doc, value).errors.each do |e|
          PDD.log.error e
          total += 1
        end
      end
      raise PDD::Error, "#{total} errors, see log above" unless total == 0
      xml
    end

    def sanitize(xml)
      xsd = Nokogiri::XML::Schema(
        File.read(File.join(File.dirname(__FILE__), '../assets/puzzles.xsd'))
      )
      errors = xsd.validate(Nokogiri::XML(xml)).map(&:message)
      errors.each { |e| PDD.log.error e }
      PDD.log.error(xml) unless errors.empty?
      raise SchemaError, errors.join('; ') unless errors.empty?
      xml
    end
  end
end
