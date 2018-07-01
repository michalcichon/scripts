#!/usr/bin/env ruby

LOCALIZABLE = "Localizable.strings"
LPROJ = ".lproj"

path = ARGV[0]
base_lang = ARGV[1]

def get_string(filepath)
    f = File.open(filepath, "r")
    str = f.read
    f.close
    return str
end

if path.nil? || base_lang.nil?
    puts "Usage: \t\t\033[1m" + __FILE__ + "\033[0m <path_to_localizables> <base_language>"
    puts "Example: \t\033[1m" + __FILE__ + "\033[0m ../../path/to/my/project/ en"
    abort
end

base_file_path = path + base_lang + LPROJ + "/" + LOCALIZABLE

if !File.exist?(base_file_path)
    puts "Base file not found for: " + base_lang
    abort
end

lint_cmd = "plutil -lint \"#{base_file_path}\""
lint_result = `#{lint_cmd}`

if !lint_result.include? "OK"
    puts "Base file is incorrect"
    puts lint_result
    abort
end

base_str = get_string(base_file_path)
base_hash = Hash.new
base_ok = true

a = base_str.split(";\n")

a.each { |line|
    t = line.split(/\s*=\s*/)
    key = t[0].strip
    value = t[1].strip
    if base_hash.key?(key)
        puts "💩 Duplicated key: #{key}"
        base_ok = false
    end
    base_hash[key] = value
}

if base_ok 
    puts "----\n✅ Base localizable OK"
else
    puts "----\n⛔️ Base localizable is not OK"
end

Dir.chdir(path)
subdir_list = Dir["*"].reject{ |o| not File.directory?(o) or !o.include? LPROJ }

subdir_list.each { |subdir|
    next if subdir.include? base_lang
    lang_path = path + subdir + "/" + LOCALIZABLE
    next if !File.exist?(lang_path)
    
    str = get_string(lang_path)
    b = str.split(";\n")
    sub_hash = Hash.new
    b.each { |line|
        t = line.split(/\s*=\s*/, 2)
        key = t[0].strip
        value = t[1].strip
        
        if sub_hash.key?(key)
            puts "💩 Duplicated key: #{key} for lang: " + subdir
        end

        if !base_hash.key?(key)
            puts "👎 Key: " + key + " of " + subdir + " is not in the base language"
        end

        sub_hash[key] = value
    }

    missing_keys = Array.new
    base_hash.each_key { |key|
        if sub_hash[key].nil?
            missing_keys.push(key)
        end
    }

    if !missing_keys.empty?
        puts "⛔️ Missing keys for language: " + subdir
        missing_keys.each { |key|
            puts "\t" + key
        }
        puts "----"
    end
}
