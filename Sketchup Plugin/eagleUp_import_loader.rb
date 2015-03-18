require "sketchup.rb"
require "extensions.rb"
# Load plugin as extension (so that user can disable it)
my_plugin_loader = SketchupExtension.new "eagleUp import", "eagleUp_import/eagleUp_import.rb"
my_plugin_loader.copyright= "2011-2015"
my_plugin_loader.creator= "J.Lamy & Neil McNeight"
my_plugin_loader.version = "4.6"
my_plugin_loader.description = "eagleUp importer, from Eagle to Sketchup."
Sketchup.register_extension my_plugin_loader, true
