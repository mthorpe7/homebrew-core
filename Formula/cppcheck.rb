class Cppcheck < Formula
  desc "Static analysis of C and C++ code"
  homepage "https://sourceforge.net/projects/cppcheck/"
  url "https://github.com/danmar/cppcheck/archive/1.80.tar.gz"
  sha256 "20863db018d69c33648bdedcdc9d81d818b9064cc4333f0d4dc45e114bd0f000"
  head "https://github.com/danmar/cppcheck.git"

  bottle do
    rebuild 1
    sha256 "49540982e80ff4eed01a02f1e6b623e449fe16c7e587ab80f361fbc247375834" => :high_sierra
    sha256 "53738447b9ea8ffac2f20e7c7f70d307476d0bb40a2180777980cb3e530c5a41" => :sierra
    sha256 "8acde65a4d657e14bdfc41337d2492cc948809f8ad42d7100524fba590635999" => :el_capitan
    sha256 "6658c569c7db35bf75bda4987f71dec24011b6f7d7b8ec1f073a17b9e9309306" => :yosemite
  end

  option "without-rules", "Build without rules (no pcre dependency)"
  option "with-qt", "Build the cppcheck GUI (requires Qt)"

  deprecated_option "no-rules" => "without-rules"
  deprecated_option "with-gui" => "with-qt"
  deprecated_option "with-qt5" => "with-qt"

  depends_on "pcre" if build.with? "rules"
  depends_on "qt" => :optional

  needs :cxx11

  def install
    ENV.cxx11

    # Man pages aren't installed as they require docbook schemas.

    # Pass to make variables.
    if build.with? "rules"
      system "make", "HAVE_RULES=yes", "CFGDIR=#{prefix}/cfg"
    else
      system "make", "HAVE_RULES=no", "CFGDIR=#{prefix}/cfg"
    end

    # CFGDIR is relative to the prefix for install, don't add #{prefix}.
    system "make", "DESTDIR=#{prefix}", "BIN=#{bin}", "CFGDIR=/cfg", "install"

    # Move the python addons to the cppcheck pkgshare folder
    (pkgshare/"addons").install Dir.glob(bin/"*.py")

    if build.with? "qt"
      cd "gui" do
        if build.with? "rules"
          system "qmake", "HAVE_RULES=yes",
                          "INCLUDEPATH+=#{Formula["pcre"].opt_include}",
                          "LIBS+=-L#{Formula["pcre"].opt_lib}"
        else
          system "qmake", "HAVE_RULES=no"
        end

        system "make"
        prefix.install "cppcheck-gui.app"
      end
    end
  end

  test do
    # Execution test with an input .cpp file
    test_cpp_file = testpath/"test.cpp"
    test_cpp_file.write <<-EOS.undent
      #include <iostream>
      using namespace std;

      int main()
      {
        cout << "Hello World!" << endl;
        return 0;
      }

      class Example
      {
        public:
          int GetNumber() const;
          explicit Example(int initialNumber);
        private:
          int number;
      };

      Example::Example(int initialNumber)
      {
        number = initialNumber;
      }
    EOS
    system "#{bin}/cppcheck", test_cpp_file

    # Test the "out of bounds" check
    test_cpp_file_check = testpath/"testcheck.cpp"
    test_cpp_file_check.write <<-EOS.undent
      int main()
      {
      char a[10];
      a[10] = 0;
      return 0;
      }
    EOS
    output = shell_output("#{bin}/cppcheck #{test_cpp_file_check} 2>&1")
    assert_match "out of bounds", output

    # Test the addon functionality: sampleaddon.py imports the cppcheckdata python
    # module and uses it to parse a cppcheck dump into an OOP structure. We then
    # check the correct number of detected tokens and function names.
    addons_dir = pkgshare/"addons"
    cppcheck_module = "#{name}data"
    expect_token_count = 55
    expect_function_names = "main,GetNumber,Example"
    assert_parse_message = "Error: sampleaddon.py: failed: can't parse the #{name} dump."

    sample_addon_file = testpath/"sampleaddon.py"
    sample_addon_file.write <<-EOS.undent
      #!/usr/bin/env python
      """A simple test addon for #{name}, prints function names and token count"""
      import sys
      import imp
      # Manually import the '#{cppcheck_module}' module
      CFILE, FNAME, CDATA = imp.find_module("#{cppcheck_module}", ["#{addons_dir}"])
      CPPCHECKDATA = imp.load_module("#{cppcheck_module}", CFILE, FNAME, CDATA)

      for arg in sys.argv[1:]:
          # Parse the dump file generated by #{name}
          configKlass = CPPCHECKDATA.parsedump(arg)
          if len(configKlass.configurations) == 0:
              sys.exit("#{assert_parse_message}") # Parse failure
          fConfig = configKlass.configurations[0]
          # Pick and join the function names in a string, separated by ','
          detected_functions = ','.join(fn.name for fn in fConfig.functions)
          detected_token_count = len(fConfig.tokenlist)
          # Print the function names on the first line and the token count on the second
          print "%s\\n%s" %(detected_functions, detected_token_count)
    EOS

    system "#{bin}/cppcheck", "--dump", test_cpp_file
    test_cpp_file_dump = "#{test_cpp_file}.dump"
    assert_predicate testpath/test_cpp_file_dump, :exist?
    python_addon_output = shell_output "python #{sample_addon_file} #{test_cpp_file_dump}"
    assert_match "#{expect_function_names}\n#{expect_token_count}", python_addon_output
  end
end
