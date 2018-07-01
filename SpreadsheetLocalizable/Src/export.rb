#!/usr/bin/env ruby

require 'rspreadsheet'

LOCALIZABLE = "Localizable.strings"
LPROJ = ".lproj"
BOOK = File.expand_path(File.dirname(__FILE__)) + "/../Output/Localizable.ods"

path = ARGV[0]

def get_string(filepath)
    f = File.open(filepath, "r")
    str = f.read
    f.close
    return str
end

if path.nil?
    puts "Usage: \t\t\033[1m" + __FILE__ + "\033[0m <path_to_localizables>"
    puts "Example: \t\033[1m" + __FILE__ + "\033[0m ../../path/to/my/project/"
    abort
end

if !File.directory?(path)
    puts "⛔️ Directory " + path + " not found"
    abort
end

Dir.chdir(path)
subdir_list = Dir["*"].reject { |o| not File.directory?(o) or !o.include? LPROJ }
subdir_list = subdir_list.select { |dir| File.file?(dir + "/" + LOCALIZABLE) }

languages = Hash.new
all_keys = Hash.new

subdir_list.each { |subdir|
    lang_path = subdir + "/" + LOCALIZABLE
    lang = subdir.gsub(LPROJ,"")
    lang_hash = Hash.new
    str = get_string(lang_path)
    lines = str.split(";\n")
    lines.each { |line|
        t = line.split(/\s*=\s*/, 2)
        key = t[0].strip.gsub(/(^|\b)"/,"")
        value = t[1].strip.gsub(/(^|\b)"/,"").gsub(/"$/,"")
        all_keys[key] = value
        lang_hash[key] = value
        puts value
    }
    languages[lang] = lang_hash
}

book = Rspreadsheet::Workbook.new
sheet = book.create_worksheet "Translations"

book.save(BOOK)
