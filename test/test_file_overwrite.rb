# -*- encoding: utf-8 -*-

# Author: M. Sakano (Wise Babel Ltd)
# License: MIT

# require 'tempfile'
# require 'fileutils'
require 'file_overwrite/file_overwrite'

$stdout.sync=true
$stderr.sync=true
# print '$LOAD_PATH=';p $LOAD_PATH

#################################################
# Unit Test
#################################################

#if $0 == __FILE__
  gem "minitest"
  # require 'minitest/unit'
  require 'minitest/autorun'
  # MiniTest::Unit.autorun

  class TestUnitFileOverwrite < MiniTest::Test
    T = true
    F = false
    SCFNAME = File.basename(__FILE__)
    FO = FileOverwrite

    def setup
      @tmpioin = Tempfile.new
      @tmpioin.sync=true 

      @orig_path  = @tmpioin.path
      @orig_content = "1 line A\n2 line B\n3 line C\n"
      @orig_mtime = Time.now - 86400  # A day earlier

      @tmpioin.print @orig_content
      reset_mtime
    end

    def teardown
      @tmpioin.close
    end

    def reset_mtime(fname=@tmpioin.path)
      FileUtils.touch fname, :mtime => @orig_mtime
    end

    def create_template_file
      io = Tempfile.new
      io.sync=true 
      io.print @orig_content
      reset_mtime(io.path)
      io
    end

    def test_initialize01
      # Testing backup file name
      f1 = FO.new(@tmpioin.path)
      re = /(.*)\.\d{14}\.bak$/
      assert_match(re, f1.backup)
      m = re.match f1.backup
      assert_equal @tmpioin.path, m[1]

      s = 'tekito'
      f1.backup = s
      assert_equal s, f1.backup

      assert_equal @orig_content, f1.dump

      # Testing backup file name
      f2 = FO.new(@tmpioin.path, suffix: '~')
      re = /(.*)~$/
      assert_match(re, f2.backup)
      m = re.match f2.backup
      assert_equal @tmpioin.path, m[1]
    end

    def test_backup
      file1 = create_template_file
      fpath = file1.path
      suffix1 = '.BAK'
      f1 = FO.new(fpath, suffix: suffix1)
      assert_equal fpath+suffix1, f1.backup
      assert_equal fpath+'other', f1.backup('other') # Just to see
      assert_equal fpath+suffix1, f1.backup  # No change has been made after just "seeing"
      f1.backup = fpath+'other'
      assert_equal fpath+'other', f1.backup  # Changed.
      f1.backup = fpath+suffix1
      assert_equal fpath+suffix1, f1.backup  # Reverted back
    end

    def test_open  # modify
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath)
      s = 'tekito'

      # Testing open 
      f1.open{|ior, iow|
        # Line 1
        line = ior.gets
        assert_equal 1, line.count("\n")
        assert_equal '1', line[0,1]
        iow.print line

        # Line 2
        line = ior.gets
        assert_equal 1, line.count("\n")
        assert_equal '2', line[0,1]
        iow.print line

        # Line 3
        line = ior.gets
        assert_equal 1, line.count("\n")
        assert_equal '3', line[0,1]
        iow.print line
        iow.print s
      }
      assert_equal @orig_content+s,   f1.dump

      # Testing open 
      bkupfile = f1.temporary_filename  # instance_eval{@iotmp.path}
      assert File.exist?(bkupfile)
      f1.reset
      assert f1.reset?
      refute File.exist?(bkupfile)
      assert_nil f1.temporary_filename

      # .modify
      f1.modify{|ior, iow|
        iow.print s+s
      }
      assert_equal s+s, f1.dump

      # Testing warning issued if changing to String-manipulation mode
      bkupfile = f1.temporary_filename  # instance_eval{@iotmp.path}
      assert File.exist?(bkupfile)
      
      assert_output('', /WARNING\b.+\breread/i){ f1.read{|i| s} }
      refute File.exist?(bkupfile)
      assert_nil f1.temporary_filename
    end

    def test_read
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath)

      s = 'tekito'
      f1.read{|i| s}
      assert_equal s,   f1.dump

      # Test of replace_with()
      f1.replace_with(s+s)
      assert_equal s+s, f1.dump
      assert_equal String, f1.state

      # Test of reset()
      f1.reset
      assert_equal @orig_content, f1.dump
      assert f1.fresh?
      assert f1.reset?
      assert_nil f1.state

      assert_output('', / not opened,/){ f1.run!(verbose: true) }
      assert_equal @orig_content, File.read(fpath)
      assert_in_delta(@orig_mtime, File.mtime(fpath), 1)  # 1 sec allowance
    end

    def test_open_run_noop  # modify
      file1 = create_template_file
      fpath = file1.path
      suffix1 = '.BAK'
      f1 = FO.new(fpath, suffix: suffix1)
      assert_equal fpath+suffix1, f1.backup

      s = 'tekito'
      f1.open{|ior, iow|
        iow.print ior.read + s
      }
      assert_equal IO, f1.state

      assert_output('', /Dryrun.+File.+Size.+Backup/){ f1.run!(noop: true, verbose: true) }
      # => "[Dryrun]File /var/XXX updated (Size: 18 => 24 bytes, Backup: /var/XXX.BAK)"

      sizes = f1.sizes
      assert_equal s.size, sizes[:new]-sizes[:old]
      # assert_nil f1.sizes
      assert_equal fpath+suffix1, f1.backup
      assert_in_delta(@orig_mtime, File.mtime(fpath), 1)  # b/c noop

      assert f1.completed?
      assert f1.frozen?
      assert_equal true, f1.state
      assert_raises(FileOverwriteError){ f1.run! }
      assert_equal fpath+suffix1, f1.backup
      assert_raises(FrozenError){ f1.backup = fpath+'other' }  # Can't be modified any more.
      assert_raises(FrozenError){ f1.reset }
    end


    def test_open_run_real  # modify
      file1 = create_template_file
      fpath = file1.path
      fsize = File.size fpath
      suffix1 = '.BAK'
      f1 = FO.new(fpath, suffix: suffix1)
      assert_equal fpath+suffix1, f1.backup

      s = 'tekito'
      f1.open{|ior, iow|
        iow.print ior.read + s
      }
      assert_equal IO, f1.state

      assert_output('', /File.+Size.+Backup/){ f1.run!(noop: false, verbose: true) }
      # => "File /var/XXX updated (Size: 18 => 24 bytes, Backup: /var/XXX.BAK)"

      # Sizes of the files.
      sizes = f1.sizes
      assert_equal s.size,               sizes[:new]-sizes[:old]
      assert_equal fsize,                sizes[:old]
      assert_equal File.size(f1.backup), sizes[:old]
      assert_equal File.size(fpath),     sizes[:new]

      # Timestamps of the files.
      assert_equal fpath+suffix1, f1.backup
      refute_in_delta(@orig_mtime, File.mtime(fpath), 1)
      assert_operator(@orig_mtime, '<', File.mtime(fpath))

      assert f1.completed?
      assert f1.frozen?
      assert_equal true, f1.state
      assert_raises(FileOverwriteError){ f1.run! }
      assert_equal fpath+suffix1, f1.backup
      assert_raises(FrozenError){ f1.backup = fpath+'other' }  # Can't be modified any more.
      assert_raises(FrozenError){ f1.reset }
    end

    def test_read_run_real
      file1 = create_template_file
      fpath = file1.path
      fsize = File.size fpath
      f1 = FO.new(fpath, suffix: nil)
      fbkup = f1.backup
      assert_nil fbkup

      s = 'tekito'
      f1.read{|i| i + s}
      assert_equal String, f1.state

      assert_output('', /File.+Size:[\d =>]+bytes?.$/){ f1.run!(verbose: true) }
      # => "File /var/XXX updated (Size: 18 => 24 bytes)"  (No word: "Backup")
      assert_nil f1.backup

      assert_equal @orig_content+s, File.read(fpath)

      # Sizes of the files.
      sizes = f1.sizes
      assert_equal s.size,               sizes[:new]-sizes[:old]
      assert_equal fsize,                sizes[:old]
      assert_equal @orig_content.size,   sizes[:old]
      assert_equal File.size(fpath),     sizes[:new]

      # Timestamps of the files.
      refute_in_delta(@orig_mtime, File.mtime(fpath), 1)
      assert_operator(@orig_mtime, '<', File.mtime(fpath))
    end

    def test_read_run_bang
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: true)
      s = 'tekito'

      # Test of silent as well
      assert_output('', ''){ f1.read!(verbose: nil){|i| i + s} }
      assert_equal @orig_content+s, File.read(fpath)
      sizes = f1.sizes
      assert_equal s.size,               sizes[:new]-sizes[:old]

      # Test of setsize option
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: nil)
      assert_output('', ''){ f1.read!(setsize: false){|i| i + s} }
      assert_equal @orig_content+s, File.read(fpath)
      assert_nil f1.sizes
    end
      
    def test_sub
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: true)

      f1.sub(/line/, 'xyz')
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      refute_match(/xyz/, f1.dump.split(/\n/)[1])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])

      assert_output('', ''){ f1.gsub(/line/, 'xyz') }
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      assert_match(/xyz/, f1.dump.split(/\n/)[1])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])
      
      f1.sub(/(li)(n)/, '\1' + 'k')
      assert_match(/like/, f1.dump.split(/\n/)[0])
      refute_match(/like/, f1.dump.split(/\n/)[1])
      f1.reset
      refute_match(/like/, f1.dump.split(/\n/)[0]) # not "like" but "line"

      # Failed-match case
      f1.sub(/naiyo(li)(n)/, '\1' + 'k')
      assert_match(/line/, f1.dump.split(/\n/)[0])
      assert_equal @orig_content, f1.instance_eval{@outstr}
      f1.reset

      ### The following does NOT work!
      # f1.sub(/(li)(ne)/){printf "and=(%s)(%s)", $&, $1; 'LIne'} # $1.upcase + $2

      ### MatchData extension in this method!
      f1.sub(/(li)(n)/){|_,m| m[1].upcase+m[2]} # $1.upcase + $2

      assert_match(/LIne/, f1.dump.split(/\n/)[0], "DEBUG: "+f1.dump)
      refute_match(/LIne/, f1.dump.split(/\n/)[1])
      f1.sub(/I/){nil}   # nil.to_s (as in String#sub)
      assert_match(/\bLne\b/, f1.dump.split(/\n/)[0])
      f1.sub(/L/){3}     #   3.to_s (as in String#sub)
      assert_match(/\b3ne\b/, f1.dump.split(/\n/)[0])
      f1.reset
      refute_match(/LI?ne/, f1.dump.split(/\n/)[0])
      assert_nil  f1.instance_eval{@outstr}

      # Failed-match case
      f1.sub(/naiyo(li)(n)/){|_,m| m[1].upcase+m[2]} # $1.upcase + $2
      assert_match(/line/, f1.dump.split(/\n/)[0], "DEBUG: "+f1.dump)
      f1.reset
    end


    def test_gsub
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: true)

      assert_output('', ''){ f1.gsub(/line/, 'xyz') }
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      assert_match(/xyz/, f1.dump.split(/\n/)[1])
      assert_match(/xyz/, f1.dump.split(/\n/)[2])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])

      assert_output('', ''){ f1.gsub(/line/, 'xyz', max: 1) }
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      refute_match(/xyz/, f1.dump.split(/\n/)[1])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])

      ## max option is ignored for the case without a block
      assert_output('', /WARNING\b.+\bmax/i){ f1.gsub(/line/, 'xyz', max: 2) }
      f1.reset

      assert_output(nil){ f1.gsub(/line/){ 'xyz' } }
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      assert_match(/xyz/, f1.dump.split(/\n/)[1])
      assert_match(/xyz/, f1.dump.split(/\n/)[2])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])

      assert_output('', ''){ f1.gsub(/line/, max: 2){ 'xyz' } }
      assert_match(/xyz/, f1.dump.split(/\n/)[0])
      assert_match(/xyz/, f1.dump.split(/\n/)[1])
      refute_match(/xyz/, f1.dump.split(/\n/)[2])
      f1.reset
      refute_match(/xyz/, f1.dump.split(/\n/)[0])
    end


    def test_tr
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: true)

      refute f1.empty?
      f1.tr('n', 'e').tr('i', 's')
      f1.tr('l', '')  # => "1 see A\n2 see B\n"
      assert_equal String, f1.state
      assert_match(/\bsee\b/, f1.dump.split(/\n/)[0])
      assert_match(/\bsee\b/, f1.dump.split(/\n/)[1])
      f1.tr('@', '')  # => "1 see A\n2 see B\n"

      assert_match(/\bsee\b/, f1.dump.split(/\n/)[0])  # No change

      ## tr_s ###
      f1.tr_s('e', 'i')  # => "1 si A\n2 si B\n"
      assert_equal String, f1.state
      assert_match(/\bsi\b/, f1.dump.split(/\n/)[0])
      assert_match(/\bsi\b/, f1.dump.split(/\n/)[1])

      ## tr_s! ###
      f1.reset
      assert_equal @orig_content, f1.dump

      f1.tr('l', 'L')
      assert_output(nil){ f1.tr_s!('@', '@') }  # No change, but save.  STDOUT/ERR suppressed.
      assert_equal @orig_content.tr('l', 'L'), File.read(fpath)
      sizes = f1.sizes
      assert_equal 0, sizes[:new]-sizes[:old]
    end

    def test_each_line
      file1 = create_template_file
      fpath = file1.path
      f1 = FO.new(fpath, suffix: nil, verbose: true)

      f1.each_line{ |i|
        i.sub(/li/, 'sX')
      }.each_line{ |i|
        i.sub(/sX/, 'si')
      }
      assert_match(/\bsine\b/, f1.dump.split(/\n/)[0])
      assert_match(/\bsine\b/, f1.dump.split(/\n/)[1])

      assert_raises(ArgumentError){ f1.each_line }

      ## each_line! ###
      f1.reset
      assert_equal @orig_content, f1.dump
      assert_output(nil){ f1.each_line!{ |i| i.tr('l', 'L') } }  # No change in size, but save.  STDOUT/ERR suppressed.
      assert_equal @orig_content.tr('l', 'L'), File.read(fpath)
      sizes = f1.sizes
      assert_equal 0, sizes[:new]-sizes[:old]
    end


    def test_readlines
      file1 = create_template_file
      fpath = file1.path
      s = 'tekito'
      # print 'DEBUG:$VERBOSE=';p $VERBOSE # => true (in Testing mode?)

      f1 = FO.readlines(fpath, verbose: false){ |ea|
        assert_equal @orig_content, ea.join('')
        orig_chomp = @orig_content.chomp
        assert_equal orig_chomp.split(/\n/).size, ea.size
        assert_equal orig_chomp.split(/\n/)[0],   ea[0].chop
        assert_equal orig_chomp.split(/\n/)[-1],  ea[-1].chop
        [s]
      }
      assert_equal s, f1.dump
      assert_nil f1.temporary_filename  # No temporary file is written in Array-mode
      refute f1.verbose, sprintf("verbose=%s", f1.verbose.inspect)

      ## run!
      assert_output('', ''){f1.run}
      sizes = f1.sizes
      assert_equal @orig_content.size, sizes[:old]
      assert_equal s.size,             sizes[:new]
    end

  end	# class TestUnitFileOverwrite < MiniTest::Test

#end	# if $0 == __FILE__


