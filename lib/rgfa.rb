# (c) 2016, Giorgio Gonnella, ZBH, Uni-Hamburg <gonnella@zbh.uni-hamburg.de>

# Main class of the RGFA library.
#
# RGFA provides a representation of a GFA graph.
# It supports creating a graph from scratch, input and output from/to file
# or strings, as well as several operations on the graph.
# The examples below show how to create a RGFA object from scratch or
# from a GFA file, write the RGFA to file, output the string representation or
# a statistics report, and control the validation level.
#
# == Interacting with the graph
#
# - {RGFA::Lines}: module with methods for finding, editing, iterating over,
#   removing lines belonging to a RGFA instance. Specialized modules exist
#   for each kind of line:
#   - {RGFA::Headers}: accessing and creating header information is done
#     using a single header line object ({#header RGFA#header})
#   - {RGFA::Segments}
#   - {RGFA::Links}
#   - {RGFA::Containments}
#   - {RGFA::Paths}
#   - {RGFA::Comments}
#
# - {RGFA::Line}: most interaction with the GFA involve interacting with
#   its record, i.e. instances of a subclass of this class. Subclasses:
#   - {RGFA::Line::Header}
#   - {RGFA::Line::Segment}
#   - {RGFA::Line::Link}
#   - {RGFA::Line::Containment}
#   - {RGFA::Line::Path}
#   - {RGFA::Line::Comment}
#
# - Further modules contain methods useful for interacting with the graph
#   - {RGFA::Connectivity} analysis of the connectivity of the graph
#   - {RGFA::LinearPaths} finding and merging of linear paths
#   - {RGFA::Multiplication} separation of the implicit instances of a repeat
#
# - Additional functionality is provided by {RGFATools}
#
# @example Creating an empty RGFA object
#   gfa = RGFA.new
#
# @example Parsing and writing GFA format
#   gfa = RGFA.from_file(filename) # parse GFA file
#   gfa.to_file(filename) # write to GFA file
#   puts gfa # show GFA representation of RGFA object
#
# @example Basic statistics report
#   puts gfa.info # print report
#   puts gfa.info(short = true) # compact format, in one line
#
# @example Validation
#   gfa = RGFA.from_file(filename, validate: 1) # default level is 2
#   gfa.validate = 3 # change validation level
#   gfa.turn_off_validations # equivalent to gfa.validate = 0
#   gfa.validate! # run post-validations (e.g. check segment names in links)
#
class RGFA
end

require_relative "./rgfa/byte_array.rb"
require_relative "./rgfa/cigar.rb"
require_relative "./rgfa/comments.rb"
require_relative "./rgfa/connectivity.rb"
require_relative "./rgfa/containments.rb"
require_relative "./rgfa/field_array.rb"
require_relative "./rgfa/field_parser.rb"
require_relative "./rgfa/field_validator.rb"
require_relative "./rgfa/field_writer.rb"
require_relative "./rgfa/multiplication.rb"
require_relative "./rgfa/headers.rb"
require_relative "./rgfa/line.rb"
require_relative "./rgfa/linear_paths.rb"
require_relative "./rgfa/lines.rb"
require_relative "./rgfa/links.rb"
require_relative "./rgfa/logger.rb"
require_relative "./rgfa/numeric_array.rb"
require_relative "./rgfa/rgl.rb"
require_relative "./rgfa/segment_ends_path.rb"
require_relative "./rgfa/segment_info.rb"
require_relative "./rgfa/segments.rb"
require_relative "./rgfa/paths.rb"
require_relative "./rgfa/sequence.rb"

class RGFA

  include RGFA::Comments
  include RGFA::Lines
  include RGFA::Headers
  include RGFA::Segments
  include RGFA::Links
  include RGFA::Containments
  include RGFA::Paths
  include RGFA::LinearPaths
  include RGFA::Connectivity
  include RGFA::Multiplication
  include RGFA::LoggerSupport
  include RGFA::RGL

  attr_accessor :validate

  # @!macro validate
  #   @param validate [Integer] (<i>defaults to: +2+</i>)
  #     the validation level; see "Validation level" under
  #     {RGFA::Line#initialize}.
  def initialize(validate: 2)
    @validate = validate
    init_headers
    @segments = {}
    @links = []
    @containments = []
    @paths = {}
    @comments = []
    @segments_first_order = false
    @progress = false
    @default = {:count_tag => :RC, :unit_length => 1}
    @extensions_enabled = false
  end

  # Require that the links, containments and paths referring
  # to a segment are added after the segment. Default: do not
  # require any particular ordering.
  #
  # @return [void]
  def require_segments_first_order
    @segments_first_order = true
  end

  # Set the validation level to 0.
  # See "Validation level" under {RGFA::Line#initialize}.
  # @return [void]
  def turn_off_validations
    @validate = 0
  end

  # List all names of segments in the graph
  # @return [Array<Symbol>]
  def segment_names
    @segments.keys.compact
  end

  # List all names of path lines in the graph
  # @return [Array<Symbol>]
  def path_names
    @paths.keys.compact
  end

  # Post-validation of the RGFA
  # @return [void]
  # @raise if validation fails
  def validate!
    validate_segment_references!
    validate_path_links!
    return nil
  end

  # Creates a string representation of RGFA conforming to the current
  # specifications
  # @return [String]
  def to_s
    s = ""
    each_line {|line| s << line.to_s; s << "\n"}
    return s
  end

  # Return the gfa itself
  # @return [self]
  def to_rgfa
    self
  end

  # Checks if the RGFA instance represents the same graph as another
  # because they have the same sequences and links but in different order.
  # @return [boolean]
  def equals(graph2)
    g1_links = Array.new
    g2_links = Array.new

    self.links.each { |x| g1_links.insert(0, x.to_s) }
    g1_links.sort!
    graph2.links.each { |x| g2_links.insert(0, x.to_s) }
    g2_links.sort!

    g1_segments = Array.new
    g2_segments = Array.new

    self.segments.each { |x| g1_segments.insert(0, x.to_s) }
    g1_segments.sort!
    graph2.segments.each { |x| g2_segments.insert(0, x.to_s) }
    g2_segments.sort!

    if g1_segments == g2_segments && g1_links == g2_links
      return true
    else
      return false
    end
  end

  # Create a copy of the RGFA instance.
  # @return [RGFA]
  def clone
    cpy = to_s.to_rgfa(validate: 0)
    cpy.validate = @validate
    cpy.enable_progress_logging if @progress
    cpy.require_segments_first_order if @segments_first_order
    return cpy
  end

  # Populates a RGFA instance reading from file with specified +filename+
  # @param [String] filename
  # @raise if file cannot be opened for reading
  # @return [self]
  def read_file(filename)
    if @progress
      linecount = `wc -l #{filename}`.strip.split(" ")[0].to_i
      progress_log_init(:read_file, "lines", linecount,
                        "Parse file with #{linecount} lines")
    end
    File.foreach(filename) do |line|
      self << line.chomp
      progress_log(:read_file) if @progress
    end
    progress_log_end(:read_file) if @progress
    validate! if @validate >= 1
    self
  end

  # Creates a RGFA instance parsing the file with specified +filename+
  # @param [String] filename
  # @raise if file cannot be opened for reading
  # @!macro validate
  # @return [RGFA]
  def self.from_file(filename, validate: 2)
    gfa = RGFA.new(validate: validate)
    gfa.read_file(filename)
    return gfa
  end

  # Write RGFA to file with specified +filename+;
  # overwrites it if it exists
  # @param [String] filename
  # @raise if file cannot be opened for writing
  # @return [void]
  def to_file(filename)
    File.open(filename, "w") {|f| each_line {|l| f.puts l}}
  end

  # Output basic statistics about the graph's sequence and topology
  # information.
  #
  # @param [boolean] short compact output as a single text line
  #
  # Compact output has the following keys:
  # - +ns+: number of segments
  # - +nl+: number of links
  # - +cc+: number of connected components
  # - +de+: number of dead ends
  # - +tl+: total length of segment sequences
  # - +50+: N50 segment sequence length
  #
  # Normal output outputs a table with the same information, plus some
  # additional one: the length of the largest
  # component, as well as the shortest and largest and 1st/2nd/3rd quartiles
  # of segment sequence length.
  #
  # @return [String] sequence and topology information collected from the graph.
  #
  def info(short = false)
    q, n50, tlen = lenstats
    nde = n_dead_ends()
    pde = "%.2f%%" % ((nde.to_f*100) / (segments.size*2))
    cc = connected_components()
    cc.map!{|c|c.map{|sn|segment!(sn).length!}.inject(:+)}
    if short
      return "ns=#{segments.size}\t"+
             "nl=#{links.size}\t"+
             "cc=#{cc.size}\t"+
             "de=#{nde}\t"+
             "tl=#{tlen}\t"+
             "50=#{n50}"
    end
    retval = []
    retval << "Segment count:               #{segments.size}"
    retval << "Links count:                 #{links.size}"
    retval << "Total length (bp):           #{tlen}"
    retval << "Dead ends:                   #{nde}"
    retval << "Percentage dead ends:        #{pde}"
    retval << "Connected components:        #{cc.size}"
    retval << "Largest component (bp):      #{cc.last}"
    retval << "N50 (bp):                    #{n50}"
    retval << "Shortest segment (bp):       #{q[0]}"
    retval << "Lower quartile segment (bp): #{q[1]}"
    retval << "Median segment (bp):         #{q[2]}"
    retval << "Upper quartile segment (bp): #{q[3]}"
    retval << "Longest segment (bp):        #{q[4]}"
    return retval
  end

  # Counts the dead ends.
  #
  # Dead ends are here defined as segment ends without connections.
  #
  # @return [Integer] number of dead ends in the graph
  #
  def n_dead_ends
    segments.inject(0) do |n,s|
      [:E, :B].each {|e| n+= 1 if links_of([s.name, e]).empty?}
      n
    end
  end

  # Compare two RGFA instances.
  # @return [Boolean] are the lines of the two instances equivalent?
  def ==(other)
    segments == other.segments and
      links == other.links and
      containments == other.containments and
      headers == other.headers and
      paths == other.paths
  end

  private

  def lenstats
    sln = segments.map(&:length!).sort
    n = sln.size
    tlen = sln.inject(:+)
    n50 = nil
    sum = 0
    sln.reverse.each do |l|
      sum += l
      if sum >= tlen/2
        n50 = l
        break
      end
    end
    q = [sln[0], sln[(n/4)-1], sln[(n/2)-1], sln[((n*3)/4)-1], sln[-1]]
    return q, n50, tlen
  end

  # Checks that L, C and P refer to existing S.
  # @return [void]
  # @raise [RGFA::LineMissingError] if validation fails
  def validate_segment_references!
    @segments.values.each do |s|
      if s.virtual?
        raise RGFA::LineMissingError, "Segment #{s.name} does not exist\n"+
            "References to #{s.name} were found in the following lines:\n"+
              s.all_references.map(&:to_s).join("\n")
      end
    end
    return nil
  end

  # Checks that P are supported by links.
  # @return [void]
  # @raise if validation fails
  def validate_path_links!
    @paths.values.each do |pt|
      pt.links.each do |l, dir|
        if l.virtual?
          raise RGFA::LineMissingError, "Link: #{l.to_s}\n"+
          "does not exist, but is required by the paths:\n"+
          l.paths.map{|pt2, dir2|pt2.to_s}.join("\n")
        end
      end
    end
    return nil
  end

  def init_headers
    @headers = RGFA::Line::Header.new([], validate: @validate)
  end

end

# Ruby core String class, with additional methods.
class String

  # Converts a +String+ into a +RGFA+ instance. Each line of the string is added
  # separately to the gfa.
  # @return [RGFA]
  # @!macro validate
  def to_rgfa(validate: 2)
    gfa = RGFA.new(validate: validate)
    split("\n").each {|line| gfa << line}
    gfa.validate! if validate >= 1
    return gfa
  end

end

# Ruby core Array class, with additional methods.
class Array

  # Converts an +Array+ of strings or RGFA::Line instances
  # into a +RGFA+ instance.
  # @return [RGFA]
  # @!macro validate
  def to_rgfa(validate: 2)
    gfa = RGFA.new(validate: validate)
    each {|line| gfa << line}
    gfa.validate! if validate >= 1
    return gfa
  end

end
