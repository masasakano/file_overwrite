
# FileOverwrite - Controller class to overwrite a file with/without a backup file

## Summary

This class provides a Ruby-oriented scheme to safely overwrite an existing
file, leaving a backup file unless specified otherwise.  It writes a temporary
file first, which is renamed to the original file in one action.  It accepts a
block like some IO or Array class-methods (e.g., `each_line` and `readlines`)
and chaining like String methods (e.g., `read`, `sub` and `gsub`).

This library realises a simple and secure handling to overwrite a file on the
spot like "-i" command-line option in Ruby, but inside a Ruby script (rather
than globally as in "-i" option) and with much more flexibility.

The master of this README file, as well as the document for all the methods,
is found in
[RubyGems/file_overwrite](https://rubygems.org/gems/file_overwrite) where all
the hyperlinks are active.

## Install

This script requires [Ruby](http://www.ruby-lang.org) Version 2.0 or above.

Although it is preferable to set the RUBYLIB environment variable to the
library directory to this gem, which is
    /THIS/GEM/LIBRARY/PATH/file_overwrite/lib

it is not essential.  You can simply require the main library file,
file_overwrite.rb, from your Ruby script and it should work, except some error
messages can be less helpful in that case.

## Examples

### Basic examples (short-hand versions)

The following six examples perform the identical operations.

    f1 = FileOverwrite.new('a.txt'); f1.open{|ior, iow| iow.print ior.read.upcase}.save!
    f2 = FileOverwrite.open!('b.txt'){|ior, iow| iow.print ior.read.upcase}
    f3 = FileOverwrite.read!('c.txt'){|s| s.upcase}
    f4 = FileOverwrite.read('d.txt').sub!(/.*/m){$&.upcase}
    f5 = FileOverwrite.each_line!('e.txt'){|s| s.upcase}
    f6 = FileOverwrite.readlines!('f.txt'){|a| a.map{|i| i.upcase}}

    f6.path    # => "f.txt"
    f6.backup  # => "f.txt.20180915.bak"
    f6.sizes   # => { :old => 40, :new => 40 }

The first example (f1) is the basic form of the use of this class.  You create
a class instance by the constructor, perform a manipulataion(s) to modify the
content, and **save** it, which means **run** the overwriting operation of the
original file.  Until you **run**, the original file unchanges, while any
modifications are stored either in the memory or a temporary file, either of
which would be garbage-collected if the process is not **run** in the end. A
backup file is automatically created, unless explicity suppressed, whose
filename or suffix is either automatically chosen or specified explicitly by
the caller.  Any parts of the operations are chainable or separatable, as you
like.

In this example, the main manipuration of modification is **IO-type**, or
File.open-type.  You are responsible to manually read the content of the
existing file and write the updated content.  This is the least memory-heavy
manipulation and so is most suitable when the original file is huge.

The second example (f2) is just a short hand of it.

The third and fourth examples (f3 and f4) are **String-type**, or
IO.read-like. You handle the entire content of the file as a single String. 
The fourth example demonstrates an example of chaining manipulations.

The fifth example (f5) is another **String-type** manipulation.  You
manipulate the content of the file line by line as a String in the iterator
(aka block), as in `IO.each_line`. Although technically {FileOverwrite#read}
is all you need for the String-type manipulation, given you can do any
manipulation you like, including String#sub and the equivalent one to
{FileOverwrite#each_line}, in the block, a few more String-type manipulations
are defined for convenience (see below).

The sixth example (f6) is **Array-type** manipulation.  You get the entire
content of the file as an Array, each element of which corresponds to a line
in the file just as `IO.readlines`. You manipulate it and return an Array,
which will be then joined and output to the original file to overwrite it when
you save.

Any methods with the name ending with a bang sign '!' implies it automatically
`run!` (or `save!`) the final overwriting process, as soon as the manipulation
of content modification finishes.

### Chaining example (with noop, meaning dryrun)

    f1 = FileOverwrite.new('a.txt', noop: true, verbose: true)
      # Treat the content as String
    f1.sub(/abc/, 'xyz').gsub(/(.)ef/){$1}.run!
    f1.completed?  # => true
    f1.sizes   # => { :old => 40, :new => 50 }
    f1.backup  # => 'a.txt.20180915.bak'
               # However, the file has not been created
               # and the original file has not been modified, either,
               # due to the noop option

### IO.read type manipulation (String-based block)

    f2 = FileOverwrite.new('a.txt', suffix: '~')
    f2.backup  # => 'a.txt~'
    f2.completed?  # => false
      # Treat the content as String inside the block
    f2.read{ |str| "\n" + i + "\n" }.gsub(/a\nb/m, '').run!
    f2.completed?  # => true
    FileOverwrite.new('a.txt', suffix: '~').sub(/a/, '').run!
      # => RuntimeError, because the backup file 'a.txt~' exists.
    FileOverwrite.new('a.txt', suffix: '~').sub(/a/, '').run!(clobber: true)
      # => The backup file is overwritten.

Note the suffix for the backup file in default consists of the date and time
of the day up to 1 second precision.  Therefore, if you stick to the default,
even if you run the same process to the same file with some interval (longer
than 1 second), the original file will not be overwritten, although that also
means there will be multiple backup files for different versions of the file.

### File.open type manipulation (IO-based block)

    f3 = FileOverwrite.new('a.txt', backup: '/tmp/b.txt')
      # Backup file can be explicitly specified.
    f3.backup  # => '/tmp/b.txt'
    f3.backup = 'original.txt'
    f3.backup  # => 'original.txt'
      # Treat the file as IO inside the block
    f3.open{ |ior, iow| i + "XYZ" }
    f3.reset   # The modification is discarded
    f3.reset?  # => true
    f3.open{ |ior, iow| i + "XYZ"; raise FileOverwriteError, 'I stop.' }
               # To discard the modification inside the block
    f3.reset?  # => true
    f3.open{ |ior, iow| "\n" + i + "\n" }
    f3.run!(noop: true, verbose: true)  # Dryrun
    f3.completed?  # => true
    f3.backup = 'change.d'  # => FrozenError (the state can not be modified after run!(), including dryrun)

### IO.readlines type manipulation (Array-based block)

    f4 = FileOverwrite.new('a.txt', suffix: nil)
    f4.backup  # => nil (No backup file is created.)
    f4.readlines{|ary| ary+["last\n"]}.each{|i| 'XX'+i}.run!
    # The content of the file is,
    IO.readlines('a.txt')[-1]   # => "XXlast\n"

### If the file is examined but if the content is not updated?

    f5 = FileOverwrite.new('a.txt', suffix: '.bak')
    f5.backup  # => 'a.txt.bak'
    f5.read{|i| i}.run!
    FileUtils.identical? 'a.txt', 'a.txt.bak'       # => true
    File.mtime('a.txt') == File.mtime('a.txt.bak')  # => true
      # To forcibly update the Timestamp, give touch option as true
      # either in new() or run!(), ie., run!(touch: true)

Note if the input file is not touched at all, the file is never **touch**-ed,
regardless of the touch option:

    FileOverwrite.new('a.txt', touch: true).run!  # => No operation

## Description

Output is via +FileUtils#fu_output_message+ and in practice messages are
output to STDERR.

### Content manipulation

Three types of manipulation for the content of the file to update are allowed:
IO, String, and Array.

#### IO-type manipulation

The only IO-type manipulation is

*   `open` (or `modify`)


Two block parameters of IO instances are given (read and write in this order).
What is output (i.e., IO#print method) with the write-descriptor inside the
block will be the content of the overwritten file.

This method can **not** be chained.  Once you call the method for
manipulation, you have to either {FileOverwrite#run!}, or
{FileOverwrite#reset} and do manipulation from the beginning.  For
convenience, the same method names with the trailing '!' are defined
({FileOverwrite#open!} and {FileOverwrite#modify!}), with which
{FileOverwrite#run!} will be performed automatically.

The class method {FileOverwrite.open!} (or {FileOverwrite.modify!}) is also
available to skip the constructor and perform {FileOverwrite.run!} (or
`save!`) straightaway.

#### String-type manipulation

String-type manipulation includes

*   `read` (with block; like IO.read)
*   `sub`  (with or without block)
*   `gsub` (with or without block; nb., as an extension from String#gsub the
    maximum number of matches can be specified with the optional argument
    max.)
*   `tr`
*   `tr_s`
*   `replace_with` (same as String#replace, but can be chained)
*   `each_line` (with block)


These methods must return String (or its equivalent) that will be written in
the updated file. Those that take block never return Enumerator (like
String#sub).

The biggest advantage is you can chain these methods, before calling
{FileOverwrite#run!}, as in the examples above.

Note that "each"-something-type methods in this class are the short-hands of
the following, and expect each iterator returns String:
    fo.read{ |allstr| 
      outstr = ''
      allstr.each_line do |i|
        # Do whatever
        outstr << result
      end
      outstr
    }

Just like IO-type methods, they can be called with a trailing '!' to perform
{FileOverwrite#run!} straightaway.

Note that once you call one of manipulations of this type, the entire content
of the input file is stored in the memory until {FileOverwrite#run!} is called
and the object is GC-ed.  For a very large file, IO-type manipulation is more
appropriate.

For `read` (`read!`) and `each_line` (`each_line!`), the class methods of the
same names are is available to skip the constructor.

#### Array-type manipulation

Similarly, an Array-type manipulation is defined:

*   `readlines`


The block for the `readlines` method must return either Array (or its
equivalent) or String.  If an Array returned, another `readlines` method can
be called again (or chained), and in the end the elements are simply
concatnated when they are written in the updated file.  If a String is
returned, any subsequent methods of manipulation must be String-type
manipulations before {FileOverwrite#run!}.

Just like IO-type methods, this can be called with a trailing '!' to perform
{FileOverwrite#run!} straightaway.

The class method {FileOverwrite.readlines} (and `readlines!`) is available to
skip the constructor.

### Other methods

#### Those related to the state

{FileOverwrite#fresh?}
:   True if the process has not begun (the file is not read, yet)
{FileOverwrite#ready?}
:   True if it is ready to output (overwriting the file)
{FileOverwrite#reset}
:   Cancel the current processing and start the text processing from the
    beginning, as read from the original file.
{FileOverwrite#chainable?}
:   True if the current state is chainable with other methods, namely in the
    String- or Array-type manipulations.
{FileOverwrite#completed?}
:   True if the overwriting process has been completed, and the instance is
    frozen.
{FileOverwrite#state}
:   True if completed, nil if {FileOverwrite#fresh?}, or Class (IO, String,
    Array), depending on which type of manipulation has been in place.
{FileOverwrite#empty?}
:   Synonym of {FileOverwrite#dump}.empty?
{FileOverwrite#end_with?}
:   Synonym of {FileOverwrite#dump}.end_with?
{FileOverwrite#force_encoding}(enc)
:   Sets the encoding of the current or to-be-read String (or Array).  The
    encoding set is not affected even after {FileOverwrite#reset}
{FileOverwrite#valid_encoding?}
:   As in `String#valid_encoding?`  Note this returns nil if
    {FileOverwrite#completed?}


#### Those related to the parameters

Note none of the write-methods are available once {FileOverwrite#completed?}

{FileOverwrite#backup}
:   (read/write) Filename (String) of the backup file.
{FileOverwrite#dump}
:   Dump the String of the original file if {FileOverwrite#fresh?}, the
    current one to be output if in the middle of process, or that of the
    written file if {FileOverwrite#completed?}
{FileOverwrite#encode}
:   Converts the internal encoding of the current or to-be-read String (or
    Array), i.e., the encoding of String passed to the user would be this
    encoding, providing the conversion goes successfully.
{FileOverwrite#sizes}
:   (read-only) Hash of :old and :new files of the sizes. This is set only
    after {FileOverwrite#run!}  If both setsize and verbose options are false
    in {FileOverwrite#run!} (the former is true in default), the file size
    calculation is suppressed and hence this returns nil.
{FileOverwrite#verbose}
:   (read/write) The default value is set in the constructor, which can be
    overwritten any time with this method, and for temporarily in
    {FileOverwrite#run!}
{FileOverwrite#ext_enc_old}, {FileOverwrite#ext_enc_new}
:   (read/write) Character-encoding of the file to read and write,
    respectively. The former can be overwritten with the
    {FileOverwrite#force_encoding}(enc) method, too.
{FileOverwrite#int_enc}
:   (read/write) If set, Character-encoding of the String read from the file
    is (attempted to be) converted into this before user's processing. This
    can be overwritten with the {FileOverwrite#encode}() method, too.
{FileOverwrite#last_match}
:   (read/write) To read (and write if need be) Regexp.last_match after
    {FileOverwrite#sub} or {FileOverwrite#gsub}.  If a block is given to them,
    `Regexp.last_match` in the caller's scope reflects the result.  However,
    if a block is not given, it does not, and hence this method is the only
    way to access the last match. See Section "Known bugs" for detail.


## Developer's note

The source codes are annotated in the [YARD](https://yardoc.org/) format. You
can view it in
[RubyGems/file_overwrite](https://rubygems.org/gems/file_overwrite).

### Algorithm

1.  The manipulated results are held either in the memory or in a temporary
    file if IO-based manipulation.
2.  Then when you perform {FileOverwrite#run!}, the following is done in one
    go:
    1.  the manipulated results are output to a temporary file if not done so,
        yet (String- or Array-based manipulations),
    2.  the original file is backed up to the specified backup file,
    3.  the temporary file is renamed to the original file,
    4.  if it is instructed to leave no backup file, the backup file is
        deleted.

3.  After {FileOverwrite#run!}, the instance of this class is still accessible
    but frozen.


If {FileOverwrite#run!} or its equivalent is not performed, the temporary file
will be deleted by GC.

### Tests

Ruby codes under the directory `test/` are the test scripts. You can run them
from the top directory as `ruby test/test_****.rb` or simply run `make test`.

## Known bugs

1.  After every execution of {FileOverwrite#sub} and {FileOverwrite#gsub}, if
    a block is given to them, `Regexp.last_match` (or +$~+) in the caller's
    scope reflects the result.  However, if a block is not given, it does not,
    and they retain the values before calling {FileOverwrite#sub} etc in the
    local scope. The value of MatchData of the last match in such cases is
    accessible via {FileOverwrite#last_match}.


## Copyright

Author
:   Masa Sakano < info a_t wisebabel dot com >
Versions
:   The versions of this package follow Semantic Versioning (2.0.0)
    http://semver.org/


