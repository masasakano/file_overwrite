# -*- encoding: utf-8 -*-

require 'fileutils'
require 'tempfile'
begin
  require 'file_overwrite/file_overwrite_error'
rescue LoadError
  # In case this file is singly used.
  warn 'Failed to load file_overwrite/file_overwrite_error.rb .  It is not essential, except some error messages can be less helpful.' if $DEBUG
end

# Controller class to backup a file and overwrite it
#
# Ruby iterators and chaining-methods are fully exploited to edit the file.
#
# = Examples
#
#   f1 = FileOverwrite.new('a.txt', noop: true, verbose: true)
#     # Treat the content as String
#   f1.sub(/abc/, 'xyz').gsub(/(.)ef/){|i| $1}.run!
#   f1.sizes   # => { :old => 40, :new => 50 }
#   f1.backup  # => 'a.txt.20180915.bak'
#              # However, the file has not been created
#              # and the original file has not been modified, either,
#              # due to the noop option
#
#   f2 = FileOverwrite.new('a.txt', suffix: '~')
#   f2.backup  # => 'a.txt~'
#   f2.completed?  # => false
#     # Treat the content as String inside the block
#   f2.read{ |str| "\n" + i + "\n" }.gsub(/a\nb/m, '').run!
#   f2.completed?  # => true
#   FileOverwrite.new('a.txt', suffix: '~').sub(/a/, '').run!
#     # => RuntimeError, because the backup file 'a.txt~' exists.
#   FileOverwrite.new('a.txt', suffix: '~').sub(/a/, '').run!(clobber: true)
#     # => The backup file is overwritten.
#
#   f3 = FileOverwrite.new('a.txt', backup: '/tmp/b.txt')
#     # Backup file can be explicitly specified.
#   f3.backup  # => '/tmp/b.txt'
#   f3.backup = 'original.txt'
#   f3.backup  # => 'original.txt'
#     # Treat the file as IO inside the block
#   f3.open{ |ior, iow| i + "XYZ" }
#   f3.reset   # The modification is discarded
#   f3.reset?  # => true
#   f3.open{ |ior, iow| i + "XYZ"; raise FileOverwriteError, 'I stop.' }
#              # To discard the modification inside the block
#   f3.reset?  # => true
#   f3.open{ |ior, iow| "\n" + i + "\n" }
#   f3.run!(noop: true, verbose: true)  # Dryrun
#   f3.completed?  # => true
#   f3.backup = 'change.d'  # => FrozenError (the state can not be modified after run!(), including dryrun)
#
#   f4 = FileOverwrite.new('a.txt', suffix: nil)
#   f4.backup  # => nil (No backup file is created.)
#   f4.readlines{|ary| ary+["last\n"]}.each{|i| 'XX'+i}.run!
#   IO.readlines('a.txt')[-1]   # => "XXlast\n"
#
#   f5 = FileOverwrite.new('a.txt', suffix: '.bak')
#   f5.backup  # => 'a.txt.bak'
#   f5.read{|i| i}.run!
#   FileUtils.identical? 'a.txt', 'a.txt.bak'       # => true
#   File.mtime('a.txt') == File.mtime('a.txt.bak')  # => true
#     # To forcibly update the Timestamp, give touch option as true
#     # either in new() or run!(), ie., run!(touch: true)
#
# @author Masa Sakano
#
class FileOverwrite
  # In order to use fu_output_message()
  include FileUtils

  # Sets the backup filename.  Read method ({#backup}) is provided separately.
  # @!attribute [w] backup
  #   @return [String]  Keys: :old and :new
  attr_writer :backup

  # Hash of the file sizes of before (:old) and after (:new).
  #
  # This is set after {#run!} and if setsize option in {#run!} is given true (Default)
  # or if verbose option is true (Def: false).  Else, nil is returned.
  #
  # @!attribute [r] sizes
  #   @return [Hash, NilClass]  Keys: :old and :new
  attr_reader :sizes

  # Verbose flag can be read or set any time, except after the process is completed
  # @!attribute [rw] verbose
  #   @return [Boolean]
  attr_accessor :verbose

  # Encoding of the content of the input file.  Default is nil (unspecified).
  # @!attribute [rw] ext_enc
  #   @return [Encoding]
  attr_accessor :ext_enc_old

  # Encoding of the content of the output file.  Default is nil (unspecified).
  # @!attribute [rw] ext_enc
  #   @return [Encoding]
  attr_accessor :ext_enc_new

  # Encoding of the content (String, Array) of the file or IO to be passed to the user.
  # @!attribute [rw] int_enc
  #   @return [Encoding]
  attr_accessor :int_enc

  # last_match from {#sub} ({#sub!}) and {#gsub}
  #
  # This values is false when uninitialised.
  # To set this value is for user's convenience only, and
  # has no effect on processing or any of the methods.
  # Every time a user runs {#sub} or {#gsub}, this value is reset.
  #
  # @!attribute [rw] last_match
  #   @return [MatchData]
  attr_accessor :last_match

  # @param fname [String] Input filename
  # @param backup: [String, NilClass] File name to which the original file is backed up.  If non-Nil, suffix is ignored.
  # @param suffix: [String, TrueClass, FalseClass, NilClass] Suffix of the backup file.  True for Def, or false if no backup.
  # @param noop: [Boolean] no-operationor dryrun
  # @param verbose: [Boolean, NilClass] the same as $VERBOSE or the command-line option -W, i.e., the verbosity is (true > false > nil).  Forced to be true if $DEBUG
  # @param clobber: [Boolean] raise Exception if false(Def) and fname exists and suffix is non-null.
  # @param touch: [Boolean] if true (non-Def), even when the file content does not change, the timestamp is updated, as long as the file is attempted to be save (#{run!} or #{save})
  # @param last_match: [MatchData, NilClass, FalseClass] To pass Regexp.last_match in Caller's scope.
  def initialize(fname, backup: nil, suffix: true, noop: false, verbose: $VERBOSE, clobber: false, touch: false, last_match: false)
    @fname = fname
    @backup = backup
    @suffix = (backup ? true : suffix)
    @noop  = noop
    @verbose = $DEBUG || verbose
    @clobber = clobber
    @touch   = touch
    @last_match = last_match

    @ext_enc_old = nil
    @ext_enc_new = nil
    @int_enc     = nil

    @outstr = nil  # String to write.  This is nil if the temporary file was already created with modify().
    @outary = nil  # or Array to write
    @iotmp  = nil  # Temporary file IO to replace the original
    @is_edit_finished = false  # true if the file modification is finished.
    @is_completed = false      # true after all the process has been completed.
    @sizes = nil
  end

  ########################################################
  # State-related methods
  ########################################################

  # Gets a path of the filename for backup
  #
  # If suffix is given, the default suffix and backup filename are ignored,
  # and the (backup) filename with the given suffix is returned
  # (so you can tell what the backup filename would be if the suffix was set).
  #
  # @param suffix [String, TrueClass, FalseClass, NilClass] Suffix of the backup file.  True for Def, or false if no backup.
  # @param backupfile: [String, NilClass] Explicilty specify the backup filename, when suffix is nil. (For internal use)
  # @return [String, NilClass]
  def backup(suffix=nil, backupfile: nil)
    return backup_from_suffix(suffix)  if suffix   # non-nil suffix explicitly given
    return backupfile                  if backupfile
    return @backup                     if @backup
    return backup_from_suffix(@suffix) if @suffix
    nil
  end


  # Returns true if the instance is chainable.
  #
  # In other words, whether a further process like {#gsub} can be run.
  # This returns nil if {#fresh?} is true.
  #
  # @return [Boolean, NilClass]
  def chainable?
    return nil if fresh?
    return false if completed?
    return !@is_edit_finished   # ie., (@outary || @outstr) b/c one of the three must be non-false after the 2 clauses above.
  end


  # Returns true if the process has been completed.
  def completed?
    @is_completed
  end


  # Returns the (current) content as String to supercede the input file
  #
  # If the file has been already overwritten, this returns the content of the new one.
  # Note it would be impossible to return the old one anyway,
  # if no backup is left, as the user chooses.
  #
  # Even if the returned string is destructively modified,
  # it has no effect on the final output to the overwritten file.
  #
  # @return [String]
  def dump
    return @outstr.dup   if @outstr
    return join_outary() if @outary
    return File.read(@iotmp.path) if @is_edit_finished && !completed?
    File.read(@fname)
  end


  # True if the (current) content to supercede the input file is empty.
  #
  # @return [String]
  def empty?
    dump.empty?
  end


  # Implement {String#encode}[https://ruby-doc.org/core-2.5.1/String.html#method-i-encode]
  #
  # If it is in the middle of the process, the internal encoding for
  # String (or Array) changes.  Note if the current proces is in the IO-mode,
  # everything has been already written in a temporary file, and hence
  # there is no effect.
  #
  # Once this is called, @int_enc is overwritten (or set),
  # and it remains so even after reset() is called.
  #
  # It is advisable to call {#force_encoding} or {#ext_enc_old=} before this is called
  # to set the encoding of the input file.
  #
  # @param *rest [Array]
  # @param **kwd [Hash]
  # @return [String]
  # @see https://ruby-doc.org/core-2.5.1/String.html#method-i-encode
  def encode(*rest, **kwd)
    enc = (rest[0] || Encoding.default_internal)
    @int_enc = enc  # raises an Exception if called after "completed"
    return enc if @is_edit_finished || fresh?
    return @outstr.encode(*rest, **kwd) if @outstr
    if @outary
      @outary.map!{|i| i.encode(*rest, **kwd)}
      return enc
    end
    raise 'Should not happen.  Contact the code developer.'
  end


  # True if the (current) content to supercede the input file end with the specified.
  #
  # Wrapper of String#end_with?
  #
  # @return [String]
  def end_with?(*rest)
    dump.end_with?(*rest)
  end


  # Implement {String#force_encoding}[https://ruby-doc.org/core-2.5.1/String.html#method-i-force_encoding]
  #
  # Once this is called, @ext_enc_old is overwritten (or set),
  # and it remains so even after reset() is called.
  #
  # @return [Encoding]
  # @see https://ruby-doc.org/core-2.5.1/String.html#method-i-force_encoding
  def force_encoding(enc)
    @ext_enc_old = enc  # raises an Exception if called after "completed"
    return enc if @is_edit_finished || fresh?
    return @outstr.force_encoding(enc) if @outstr
    if @outary
      @outary.map!{|i| i.force_encoding(enc)}
      return enc
    end
    raise 'Should not happen.  Contact the code developer.'
  end


  # Returns true if the process has not yet started.
  def fresh?
    !state
  end
  alias_method :reset?, :fresh? if ! self.method_defined?(:reset?)


  # Returns the (duplicate of the) filename to be (or to have been) updated.
  #
  # To destructively modify this value would affect nothing in the parent object.
  #
  # @return [String]
  def path
    @fname.dup
  end


  # Returns true if the instance is ready to run (to execute overwriting the file).
  def ready?
    !fresh? && !completed?
  end
  alias_method :reset?, :fresh? if ! self.method_defined?(:reset?)


  # Reset all the modification which is to be applied
  #
  # @return [NilClass]
  def reset
    @outstr = nil
    @outary = nil
    @is_edit_finished = nil
    close_iotmp  # @iotmp=nil; immediate deletion of the temporary file
    warn "The modification process is reset." if $DEBUG
    nil
  end


  # Returns the temporary filename (or nil), maybe for debugging
  #
  # It may not be open?
  #
  # @return [String, NilClass] Filename if exists, else nil
  def temporary_filename
    @iotmp ? @iotmp.path : nil
  end


  # Returns the current state
  #
  # nil if no modification has been attempted.
  # IO if the modification has been made and it is wating to run.
  # String or Array (or their equivalent), depending how it has been chained so far.
  # true if the process has been completed.
  #
  # @return [Class, TrueClass, NilClass]
  def state
    return true     if completed?
    return IO            if @is_edit_finished
    return @outstr.class if @outstr
    return @outary.class if @outary
    nil
  end

  # String#valid_encoding?()
  #
  # @note returns nil if the process has been already completed.
  #
  # @return [Boolean, NilClass]
  def valid_encoding?()
    return nil if completed?
    dump.valid_encoding?
  end


  ########################################################
  # run
  ########################################################

  # If identical, just touch (if specified) and returns true
  #
  # @param noop [Boolean]
  # @param verbose [Boolean]
  # @param touch [Boolean] if true (non-Def), when the file content does not change, the timestamp is updated
  # @return [Boolean]
  def run_identical?(noop, verbose, touch)
    if !identical?(@iotmp.path, @fname) # defined in FileUtils
      return false
    end

    @iotmp.close(true)  # immediate deletion of the temporary file

    msg = sprintf("%sNo change in (%s).", prefix(noop), @fname)
    if touch
      touch(@fname, noop: noop)          # defined in FileUtils
      msg.chop!  # chop a full stop.
      msg << " but timestamp is updated to " << File.mtime(@fname).to_s << '.'
    end
    fu_output_message msg if verbose

    @is_completed = true
    self.freeze
    true
  end
  private :run_identical?


  # Actually performs the file modification
  #
  # If setsize option is true (Default) or verbose, method {#sizes} is activated after this method,
  # which returns a hash of file sizes in bytes before and after, so you can chain it.
  # Note this method returns nil if the input file is not opened at all.
  #
  # @example With setsize option
  #   fo.run!(setsize: true).sizes
  #     # => { :old => 40, :new => 50 }
  #
  # @example One case where this returns nil
  #   fo.new('test.f').run!  # => nil
  #
  # The folloing optional parameters are taken into account.
  # Any other options are ignored.
  #
  # @param backup: [String, NilClass] File name to which the original file is backed up.  If non-Nil, suffix is ignored.
  # @param suffix: [String, TrueClass, FalseClass, NilClass] Suffix of the backup file.  True for Def, or false if no backup.
  # @param noop: [Boolean]
  # @param verbose: [Boolean]
  # @param clobber: [Boolean] raise Exception if false(Def) and fname exists and suffix is non-null.
  # @param touch: [Boolean] Even if true (non-Def), when the file content does not change, the timestamp is updated, unless aboslutely no action has been taken for the file.
  # @param setsize: [Boolean]
  # @return [NilClass, self] If the input file is not touched, nil is returned, else self.
  # @raise [FileOverwriteError] if the process has been already completed.
  def run!(backup: @backup, suffix: @suffix, noop: @noop, verbose: @verbose, clobber: @clobber, touch: @touch, setsize: true, **kwd)
    raise FileOverwriteError, 'The process has been already completed.' if completed?

    bkupname = get_bkupname(backup, suffix, noop, verbose, clobber)
    sizes = write_new(verbose, setsize)
    return nil if !sizes

    return self if run_identical?(noop, verbose, touch)

    if bkupname
      msg4bkup = ", Backup: " + bkupname if verbose
    else
      io2del = tempfile_io
      io2delname = io2del.path
    end

    fname_to = (bkupname || io2delname)
    mv(  @fname,    fname_to, noop: noop, verbose: $DEBUG) # defined in FileUtils
    begin
      mv(@iotmp.path, @fname, noop: noop, verbose: $DEBUG) # defined in FileUtils
    rescue
      msg = sprintf("Process halted! File system error in renaming the temporary file %s back to the original %s", @iotmp.path, @fname) 
      warn msg
      raise
    end

    # @iotmp.close(true)  # to immediate delete the temporary file
                          # If commented out, GC looks after it.

    File.unlink io2delname if io2delname && !noop
    # if noop, GC will delete it.

    if verbose
      msg = sprintf("%sFile %s updated (Size: %d => %d bytes%s)\n", prefix(noop), @fname, sizes[:old], sizes[:new], msg4bkup)
      fu_output_message msg
    end

    @is_completed = true
    self.freeze

    return self
  end
  alias_method :run,   :run! if ! self.method_defined?(:run)
  alias_method :save,  :run! if ! self.method_defined?(:save)
  alias_method :save!, :run! if ! self.method_defined?(:save!)


  ########################################################
  # IO-based manipulation
  ########################################################

  # Modify the content in the block (though not committed, yet)
  #
  # Two parameters are passed to the block: io_r and io_w.
  # The former is the read-descriptor to read from the original file
  # and the latter is the write-descriptor to write whatever to the temporary file,
  # which is later moved back to the original file when you {#run!}.
  #
  # Note the IO pointer for the input file is reset after this method.
  # Hence, chaining this method makes no effect (warning is issued),
  # but only the last one is taken into account.
  #
  # @example
  #   fo.modify do |io_r, io_w|
  #     io_w.print( "\n" + io_r.read + "\n" )
  #   end
  #
  # If you want to halt, undo and reset your modification process in the middle, issue
  #   raise FileOverwriteError [Your_Message]
  # and it will be rescued. Your_Message is printed to STDERR if verbose was specified in {#initialize} or $DEBUG
  #
  # @param **kwd [Hash] keyword parameters passed to File.open.  Notably, ext_enc and int_enc .
  # @return [self]
  # @yieldparam ioin [IO] Read IO instance from the original file
  # @yieldparam @iotmp [IO] Write IO instance to the temporary file
  # @yieldreturn [Object] ignored
  # @raise [ArgumentError] if a block is not given
  def modify(**kwd)
    raise ArgumentError, 'Block must be given.' if !block_given?
    normalize_status(:@is_edit_finished)

    kwd_open = {}
    kwd_open[:external_encoding] = @ext_enc_old if @ext_enc_old
    kwd_open[:internal_encoding] = @int_enc     if @int_enc
    kwd_open[:external_encoding] = (kwd[:ext_enc] || kwd_open[:external_encoding])
    kwd_open[:internal_encoding] = (kwd[:int_enc] || kwd_open[:internal_encoding])
    [:mode, :flags, :encoding, :textmode, :binmode, :autoclose].each do |es|
      # Method list from https://ruby-doc.org/core-2.5.1/IO.html#method-c-new
      kwd_open[es] = kwd[es] if kwd.key?(es)
    end

    begin
      File.open(@fname, **kwd_open) { |ioin|
        @iotmp = tempfile_io
        yield(ioin, @iotmp)
      }
    rescue FileOverwriteError => err
      warn err.message if @verbose
      reset
    end
    self
  end
  alias_method :open, :modify if ! self.method_defined?(:open)


  # Alias to self.{#modify}.{#run!}
  #
  # @return [self]
  # @yieldparam ioin [IO] Read IO instance from the original file
  # @yieldparam @iotmp [IO] Write IO instance to the temporary file
  # @yieldreturn [Object] ignored
  # @raise [ArgumentError] if a block is not given
  def modify!(**kwd, &bloc)
    modify(&bloc).run!(**kwd)
  end
  alias_method :open!, :modify! if ! self.method_defined?(:open!)


  ########################################################
  # Array-based manipulation
  ########################################################

  # Takes a block in which the entire String of the file is passed.
  #
  # IO.readlines(infile) is given to the block, where
  # Encode may be taken into account if specified already.
  #
  # The block must return an Array, the number of the elements of which
  # can be allowed to differ from the input.  The elements of the Array
  # will be joined to output to the overwritten file in the end.
  #
  # @param *rest [Array] separator etc
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yieldparam str [String]
  # @yieldreturn [String] to be written back to the original file
  def readlines(*rest, **kwd, &bloc)
    raise ArgumentError, 'Block must be given.' if !block_given?

    if :first == normalize_status(:@outary)
      adjust_input_encoding(**kwd){ |f|  # @fname
        @outary = IO.readlines(f, *rest)
      }
    end

    @outary = yield(@outary)
    self
  end


  ########################################################
  # String-based manipulation
  ########################################################

  # Takes a block in which each line of the file (or current content) is passed.
  #
  # In the block each line as String is given as a block argument.
  # Each iterator must return a String (or an object having to_s method),
  # which replaces the input String to be output to the overwritten file later.
  #
  # This method can be chained, as String-type processing.
  #
  # @param *rest [Array] separator etc
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yieldparam str [String]
  # @yieldreturn [String] to be written back to the original file
  # @raise [ArgumentError] if a block is not given
  def each_line(*rest, **kwd, &bloc)
    raise ArgumentError, 'Block must be given.' if !block_given?
    read(**kwd){ |outstr|
      outstr.each_line(*rest).map{|i| yield(i).to_s}.join('')
    }
  end

  # Alias to self.{#sub}.{#run!}
  #
  # @param *rest [Array<Regexp,String>]
  # @param **kwd [Hash] setsize: etc
  # @return [self]
  # @yield the same as {String#sub!}
  def each_line!(*rest, **kwd, &bloc)
    send(__method__.to_s.chop, *rest, **kwd, &bloc).run!(**kwd)
  end

  # # Takes a block to perform {IO#each_line} for the input file
  # #
  # # @return [self]
  # # @yieldparam *rest [Object] Read IO instance from the original file
  # # @yieldreturn [String] to be written back to the original file
  # # @raise [ArgumentError] if a block is not given
  # def each_line(*rest)
  #   raise ArgumentError, 'Block must be given.' if !block_given?
  #   modify { |io|
  #     io.each_line(*rest) do |*args|
  #       yield(*args) 
  #     end
  #   }
  #   self
  # end


  # Handler to process the entire string of the file (or current content)
  #
  # If block is not given, just sets the processing-state as String.
  #
  # Else, IO.read(infile) is given to the block.  No other options, such as length,
  # as in IO.read are accepted.  Then, the returned value is held as a String,
  # while self is returned; hence this method can be chained.
  # If the block returns nil (or Boolean), {FileOverwriteError} is raised.
  # Make sure for the block to return a String.
  #
  # Note this method does not take arguments as in IO.read .
  #
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yieldparam str [String]
  # @yieldreturn [String] to be written back to the original file
  # @raise [FileOverwriteError] if a block is given and nil or Boolean is returned.
  def read(**kwd, &bloc)
    if :first == normalize_status(:@outstr)
      adjust_input_encoding(**kwd){ |f|  # @fname
        @outstr = File.read f
      }
    end
      
    @outstr = yield(@outstr) if block_given?
    raise FileOverwriteError, 'ERROR: The returned value from the block in read() has to be String.' if !defined?(@outstr.gsub)
    warn "WARNING: Empty string returned from a block in #{__method__}" if !@verbose.nil? && @outstr.empty?
    self
  end


  # Alias to self.{#read}.{#run!}
  #
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yield Should return string
  def read!(**kwd, &bloc)
    read(**kwd, &bloc).run!(**kwd)
  end


  # Replaces the file content with the given argument like {String#replace}
  #
  # This method can be chained.
  #
  # @param str [String] the content will be replaced with this
  # @return [self]
  def replace_with(str)
    read
    @outstr = str.to_s
    self
  end


  # Alias to self.{#replace_with}.{#run!}
  #
  # @return [self]
  # @yield the same as {String#gsub!}
  def replace_with!(str, **kwd)
    replace_with(str).run!(**kwd)
  end


  # Similar to String#sub
  #
  # This method can be chained.
  # This method never returns an Enumerator.
  #
  # @note Algorithm
  #   To realise the local-scope variables like $~, $1, and Regexp.last_match to
  #   be usable inside the block as in String#sub, it overwrites them when a block
  #   is given (See the linked article for the phylosophy of how to do it).
  #   Once a block is read, those variables remain as updated values even after the block
  #   in the caller's scope, in the same way as String#sub.  However, when a block is not given,
  #   those variables are *NOT* updated, which is different from String#sub.
  #   You can retrieve the MatchData by this method via {#last_match} after {#sub}
  #   is called, if need be.
  #
  # @param *rest [Array<Regexp,String>]
  # @param max: [Integer] the number of the maximum matches.  If it is not 1, {#gsub} is called, instead.  See {#gsub} for detail.
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yield the same as String#sub
  # @see https://stackoverflow.com/questions/52359278/how-to-pass-regexp-last-match-to-a-block-in-ruby/52385870#52385870
  def sub(*rest, max: 1, **kwd, &bloc)
    return self if sub_gsub_args_only(*rest, max: max, **kwd)

    if !block_given?
      raise ArgumentError, full_method_name+' does not support the format to return an enumerator.'
    end

    if max.to_i != 1
      return gsub(*rest, max: max, **kwd, &bloc)
    end

    @last_match = rest[0].match(@outstr)
    return self if !@last_match

    # Sets $~ (Regexp.last_match) in the given block.
    # @see https://stackoverflow.com/questions/52359278/how-to-pass-regexp-last-match-to-a-block-in-ruby/52385870#52385870
    bloc.binding.tap do |b|
      b.local_variable_set(:_, $~)
      b.eval("$~=_")
    end

    # The first (and only) argument for the block is $& .
    # Returning nil, Integer etc is accepted in the block of sub/gsub
    @outstr = @last_match.pre_match + yield(@last_match[0]).to_s + @last_match.post_match
    return self
  end


  # Alias to self.{#sub}.{#run!}
  #
  # @param *rest [Array<Regexp,String>]
  # @param **kwd [Hash] setsize: etc
  # @return [self]
  # @yield the same as {String#sub!}
  def sub!(*rest, **kwd, &bloc)
    sub(*rest, &bloc).run!(**kwd)
  end


  # Similar to String#gsub
  #
  # This method can be chained.
  # This method never returns an Enumerator.
  #
  # Being different from the standard Srrint#gsub, this method accepts
  # the optional parameter max, which specifies the maximum number of times
  # of the matches and is valid ONLY WHEN a block is given.
  #
  # @note Algorithm
  #   See {#sub} for the basic algorithm.
  #   This method emulates String#gsub as much as possible (duck-typing).
  #   In String#gsub, the variable $~ after the method has the last matched characters
  #   as the matched string and the original string before the last matched characters
  #   as pre_match.  For example,
  #     'abc'.gsub(/./){$1.upcase}
  #   returns
  #     'ABC'
  #   and leaves
  #     $& == 'c'
  #     Regexp.pre_match == 'ab'
  #   It is the same in this method.
  #
  # @note Disclaimer
  #   When a block is not given but arguments only (and not expecting Enumerator to return),
  #   this method simply calls String#gsub .  However, when only 1 argument
  #   and a block is given, this method must iterate on its own, which is implemented.
  #   I am not 100% confident if this method works in the completely same way
  #   as String#gsub in every single situation, given the regular expression
  #   has so many possibilities; so far I have not found any cases where this method breaks.
  #   This method is more inefficient and slower than the original String#gsub
  #   as the iteration is implemented in pure Ruby.
  #
  # @param *rest [Array<Regexp,String>]
  # @param max: [Integer] the number of the maximum matches.  0 means no limit (as in String#gsub).  Valid only if a block is given.
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  # @yield the same as String#gsub
  # @see #sub
  # @see https://stackoverflow.com/questions/52359278/how-to-pass-regexp-last-match-to-a-block-in-ruby/52385870#52385870
  def gsub(*rest, max: 0, **kwd, &bloc)
    return sub(*rest, max: 1, **kwd, &bloc) if 1 == max  # Note: Error message would be labelled as 'sub'
    return self if sub_gsub_args_only(*rest, max: max, **kwd)

    if !block_given?
      raise ArgumentError, full_method_name+' does not support the format to return an enumerator.'
    end

    max = 5.0/0 if max.to_i <= 0

    regbase_str = rest[0].to_s
    regex = Regexp.new( sprintf('(%s)', regbase_str) ) # to guarantee the entire string is picked up by String#scan
    scans = @outstr.scan(regex)
    return self if scans.empty?  # no matches

    scans.map!{|i| [i].flatten}  # Originally, it can be a double array.
    prematch = ''
    ret = ''
    imatch = 0  # Number of matches
    scans.each do |ea_sc|
      str_matched = ea_sc[0]
      imatch += 1
      pre_size = prematch.size
      pos_end_p1 = @outstr.index(str_matched, pre_size) # End+1
      str_between = @outstr[pre_size...pos_end_p1]
      prematch << str_between
      ret      << str_between
      regex = Regexp.new( sprintf('(?<=\A%s)%s', Regexp.quote(prematch), regbase_str) )
      #regex = rest[0] if prematch.empty?  # The first run
      @last_match = regex.match(@outstr)
      prematch << str_matched

      # Sets $~ (Regexp.last_match) in the given block.
      # @see https://stackoverflow.com/questions/52359278/how-to-pass-regexp-last-match-to-a-block-in-ruby/52385870#52385870
      bloc.binding.tap do |b|
        b.local_variable_set(:_, $~)
        b.eval("$~=_")
      end

      # The first (and only) argument for the block is $& .
      # Returning nil, Integer etc is accepted in the block of sub/gsub
      ret << yield(@last_match[0]).to_s

      break if imatch >= max
    end
    ret << Regexp.last_match.post_match  # Guaranteed to be non-nil.

    @outstr = ret
    return self
  end


  # Alias to self.{#gsub}.{#run!}
  #
  # @return [self]
  # @yield the same as {String#gsub!}
  def gsub!(*rest, **kwd, &bloc)
    gsub(*rest, &bloc).run!(**kwd)
  end


  # Similar to {String#tr}
  #
  # This method can be chained.
  #
  # @param *rest [Array] replacers etc
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  def tr(*rest, **kwd)
    read(**kwd){ |outstr|
      outstr.tr!(*rest) || outstr
    }
  end

  # Alias to self.{#tr}.{#run!}
  #
  # @return [self]
  def tr!(*rest, **kwd)
    tr(*rest, **kwd).run!(**kwd)
  end

  # Similar to {String#tr_s}
  #
  # This method can be chained.
  #
  # @param *rest [Array] replacers etc
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [self]
  def tr_s(*rest, **kwd)
    read(**kwd){ |outstr|
      outstr.tr_s!(*rest) || outstr
    }
  end

  # Alias to self.{#tr}.{#run!}
  #
  # @return [self]
  def tr_s!(*rest, **kwd)
    tr_s(*rest, **kwd).run!(**kwd)
  end


  ########################################################
  # Class methods
  ########################################################

  # Class method for {FileOverwrite#initialize}.{#modify!}
  #
  # @see #initialize
  # @see #modify
  def self.modify!(*rest, **kwd, &bloc)
    new(*rest, **kwd).modify!(**kwd, &bloc)
  end
  singleton_class.send(:alias_method, :open!, :modify!)


  # Shorthand of {FileOverwrite#initialize}.{#readlines}, taking parameters for both
  #
  # @param fname [String] Input and overwriting filename
  # @param *rest [Array] (see {#initialize} and {#readlines})
  # @param **kwd [Hash] (see {#initialize})
  # @return [FileOverwrite]
  # @yield refer to {#readlines}
  # @see #readlines
  def self.readlines(fname, *rest, **kwd, &bloc)
    new(fname, *rest, **kwd).send(__method__, *rest, **kwd, &bloc)
  end


  # Shorthand of {FileOverwrite.readlines}.{#run!}
  #
  # @param  (see FileOverwrite.readlines and #run)
  # @return [FileOverwrite]
  # @yield refer to {#readlines}
  # @see #readlines
  def self.readlines!(*rest, **kwd, &bloc)
    readlines(*rest, **kwd, &bloc).run!(**kwd)
  end


  # Class method for {FileOverwrite#initialize}.{#read}
  #
  # @see #initialize
  # @see #read
  def self.read(*rest, **kwd, &bloc)
    new(*rest, **kwd).send(__method__, **kwd, &bloc)
  end

  # Class method for {FileOverwrite#initialize}.{#read!}
  #
  # @see #initialize
  # @see #read!
  def self.read!(*rest, **kwd, &bloc)
    new(*rest, **kwd).send(__method__, **kwd, &bloc)
  end

  # Class method for {FileOverwrite#initialize}.{#each_line}
  #
  # @see #initialize
  # @see #each_line
  def self.each_line(fname, *rest, **kwd, &bloc)
    new(fname, **kwd).send(__method__, *rest, **kwd, &bloc)
  end

  # Class method for {FileOverwrite#initialize}.{#each_line!}
  #
  # @see #initialize
  # @see #each_line!
  def self.each_line!(fname, *rest, **kwd, &bloc)
    new(fname, **kwd).send(__method__, *rest, **kwd, &bloc)
  end


  ########################################################
  private
  ########################################################

  # Core routine to adjust the encoding of the input String (or Array)
  #
  # @return [Array, String]
  # @yieldparam fname [String]
  # @yieldreturn [Array, String] @outstr or @outary
  def adjust_input_encoding(**kwd, &bloc)
    raise ArgumentError, 'Block must be given.' if !block_given?
    obj = yield(@fname)

    kwd_enc = {}
    kwd_enc[:ext_enc] = @ext_enc_old  if @ext_enc_old
    kwd_enc[:ext_enc] = kwd[:ext_enc] if kwd[:ext_enc]
    kwd_enc[:int_enc] = @int_enc      if @int_enc
    kwd_enc[:int_enc] = kwd[:int_enc] if kwd[:int_enc]
    if kwd_enc[:ext_enc]
      force_encoding kwd_enc[:ext_enc]
    end
    if kwd_enc[:int_enc]
      if defined? obj.map!
        obj.map!{|i| i.encode(kwd_enc[:int_enc])}
      elsif defined? obj.encode
        obj.encode kwd_enc[:int_enc]
      else
        raise 'Should not happen. Contact the code developper.'
      end
    end
  end
  private :adjust_input_encoding


  # Returns a path of the filename constructed with the supplied suffix
  #
  # @param suffix [String, TrueClass] Suffix of the backup file.  True for Def, or false if no backup.
  # @return [String, NilClass]
  def backup_from_suffix(suffix)
    raise 'Should not happen. Contact the code developper.' if !suffix

    @fname + ((suffix == true) ? Time.now.strftime(".%Y%m%d%H%M%S.bak") : suffix)
  end
  private :backup_from_suffix


  # Deletes the temporary file if exists
  #
  # @return [String, NilClass] Filename if deleted, else nil
  def close_iotmp
    return if !@iotmp
    fn = @iotmp.path
    @iotmp.close(true) if @iotmp # immediate deletion of the temporary file
    @iotmp = nil
    fn
  end
  private :close_iotmp

  # Returns a String "FileOverwrite#MY_METHOD_NAME"
  #
  # @param nested_level [Integer] 0 (Def) if the caller wants the name of itself.
  # @return [String]
  def full_method_name(nested_level=0)
    # Note: caller_locations() is equivalent to caller_locations(1).
    #       caller_locations(0) from this method would also contain the information of
    #       this method full_method_name() itself, which is totally irrelevant.
    sprintf("%s#%s", self.class.to_s, caller_locations()[nested_level].label)
  end
  private :full_method_name


  # Gets a path of the filename for backup and checks out clobber
  #
  # @param backup_l [String, NilClass] File name to which the original file is backed up.  If non-Nil, suffix is ignored.
  # @param suffix [String, TrueClass, FalseClass, NilClass] Suffix of the backup file.  True for Def, or false if no backup.
  # @param noop [Boolean]
  # @param verbose [Boolean]
  # @param clobber [Boolean] raise Exception if false(Def) and fname exists and suffix is non-null.
  # @return [String, NilClass]
  def get_bkupname(backup_l, suffix, noop, verbose, clobber)
    bkupname = backup(suffix, backupfile: backup_l)
    return nil if !bkupname

    if File.exist?(bkupname)
      raise "File(#{@fname}) exists." if !clobber
      fu_output_message sprintf("%Backup File %s is overwritten.", prefix(noop), bkupname) if verbose
    end

    bkupname
  end
  private :get_bkupname


  # Returns joined string of @outary as it is to output
  #
  # @return [String]
  def join_outary(ary=@outary)
    ary.join ''
  end
  private :join_outary


  # Changes the status of a set of instance variables
  # 
  # Returns :first if this is the first process, else :continuation (ie, chained)
  # For IO-style, this returns always :first
  # 
  # @param inst_var [Symbol, String] '@is_edit_finished', :@outary (do not forget '@')
  # @return [Symbol] :first or :continuation
  def normalize_status(inst_var)
    errmsg = "WARNING: The file (#{@fname}) is reread from the beginning."

    case inst_var
    when :@is_edit_finished, '@is_edit_finished'
      warn errmsg if @outstr || @outary
      reset
      @is_edit_finished = true
      return :first

    when :@outary, '@outary'
      warn errmsg if @outstr || @is_edit_finished
      @is_edit_finished = false
      close_iotmp  # @iotmp=nil; immediate deletion of the temporary file
      @outstr = nil
      return :continuation if @outary 
      @outary ||= []
      return :first

    when :@outstr, '@outstr'
      # For String-type processing, it is allowed if the previous processing
      # is not String-type but Array-type.
      warn errmsg if @is_edit_finished || (@outstr && @outary)
      @is_edit_finished = false
      close_iotmp  # @iotmp=nil; immediate deletion of the temporary file
      if @outary
        @outstr = join_outary()
        @outary = nil
        return :continuation
      else
        return :continuation if @outstr
        @outstr ||= ''
        return :first
      end
    else
      raise
    end
  end
  private :normalize_status


  # Returns the prefix for message for noop option
  #
  # @return [self]
  # @yield Should return String or Array (which will be simply joined)
  def prefix(noop=@noop)
    (noop ? '[Dryrun]' : '')
  end
  private :prefix


  # Common routine to process String#sub and String#gsub
  #
  # handling the case where no block is given.
  #
  # @param *rest [Array<Regexp,String>]
  # @param max: [Integer] the number of the maximum matches.  0 means no limit (as in String#gsub)
  # @param **kwd [Hash] ext_enc, int_enc
  # @return [String, NilClass] nil if not processed because a block is supplied (or error).
  # @yield the same as String#sub
  def sub_gsub_args_only(*rest, max: 1, **kwd)
    read(**kwd) 
    return if 1 == rest.size

    method = caller_locations()[0].label
    if !@verbose.nil? && ((max != 1 && 'sub' == method) ||  (max != 0 && 'gsub' == method))
      msg = sprintf "WARNING: max option (%s) of neither 0 nor 1 is given. It is ignored in %s(). Give a block (instead of just arguments) for the max option to be taken into account.", max, method
      warn msg
    end

    # Note: When 2 arguments are given, the block is simply ignored in default (in Ruby 2.5).
    @outstr.send(method+'!', *rest) # sub! or gsub! => String|nil
    @last_match = Regexp.last_match # $~
    @outstr
  end
  private :sub_gsub_args_only


  # Gets an IO of a temporary file (in the same directory as the source file)
  #
  # @return [IO]
  def tempfile_io(**kwd)
    kwd_def = {}
    kwd_def[:ext_enc] = @ext_enc_new if @ext_enc_new
    kwd_def[:int_enc] = @int_enc     if @int_enc
    kwd = kwd_def.merge kwd

    iot = Tempfile.open(File.basename(@fname) + '.' + self.class.to_s, File.dirname(@fname), **kwd)
    iot.sync=true    # Essential!
    iot
  end
  private :tempfile_io


  # Issues an warning for {#sub}/{#gsub} and {#sub!}/{#gsub!}
  #
  # @return [NilClass]
  def warn_for_sub_gsub(err)
    return if !err.message.include?('for nil:NilClass')  # and raise-d
    warn 'WARNING: The variables $1, $2, etc (and $& and Regexp.last_match) are NOT passed to the block in '+full_method_name(1)+' (if that is the cause of this Exception). Use the second block parameter instead, which is the MatchData.'
    nil
  end
  private :warn_for_sub_gsub


  # Write a temporary new file
  #
  # The Tempfile IO for the new file is set to be @iotmp (so @iotmp.path gives the filename).
  #
  # Returns either nil (if no further process is needed) or Hash.
  # The Hash would be empty if not verbose or !setsize.
  # Else it would contains the filesizes for :old and :new files.
  #
  # @param verbose [Boolean, NilClass]
  # @param setsize [Boolean] If true, @sizes is set.
  # @return [Hash, NilClass]
  def write_new(verbose, setsize=true)
    if @outstr || @outary
      @iotmp.close(true) if @iotmp  # should be redundant, but to play safe
      @iotmp = tempfile_io
      @iotmp.print (@outstr || join_outary())
      @outstr = nil
      @outary = nil
    elsif !@is_edit_finished
      warn "Input file (#{@fname}) is not opened, and hence is not modified." if !verbose.nil?
      return
    end

    return Hash.new if !verbose && !setsize

    @sizes = {
      :old => File.size(@fname),
      :new => File.size(@iotmp.path),
    }
    if @sizes[:new] == 0
      warn "The revised file (#{@fname}) is empty." if !verbose.nil?
    end
    @sizes
  end
  private :write_new


end  # class FileOverwrite

### Future A/Is
#
# def backup_base=(filename)
# end

