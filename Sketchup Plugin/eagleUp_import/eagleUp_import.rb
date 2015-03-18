=begin
Copyright 2011 J.Lamy. All rights reserved.
Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list
   of conditions and the following disclaimer in the documentation and/or other materials
   provided with the distribution.
THIS SOFTWARE IS PROVIDED BY J.Lamy ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL J.Lamy OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
Author: J.Lamy
Name: eagleUp_import
Version: 4.5
SU Version: 8
=end

require 'sketchup.rb'
USE_RELATIVE_PATH = 1	# set to 0 to keep absolute paths

class EagleUp

	@existing_faces = []
	
	# Simple function to convert string value to a real value and scale
	def strToL(strValue)
		return strValue.to_l * @scale
	end

	def connect_close_vertices(entities, vert1, vert2, threshold)
		point_distance = vert1.position.distance vert2.position
		if point_distance > 0 && point_distance < threshold
			puts "outline correct > correcting line: (" + vert1.position.to_s + ") - (" + vert2.position.to_s + ") = " + point_distance.to_s
			entities.add_line vert1, vert2
		end
	end

	def get_true_start_of_edge(edge)
		if edge.curve
			return edge.curve.first_edge.start()
		else
			return edge.start()
		end
	end

	def get_true_end_of_edge(edge)
		if edge.curve
			return edge.curve.last_edge.end()
		else
			return edge.end()
		end
	end

	
	def faceArray(entities)
		array = []
		entities.each do |entity|
			if(entity.typename == "Face")
				array[array.length] = entity
			end
		end
		return array
	end

	# Manual import from command line, will issue file dialog
	def import()
		# prompt the user for the file describing the board
		file_data_path = UI.openpanel "Import eagleUp file", "", "*.eup"
		import_file(file_data_path)
	end


	def import_file(file_data_path)
		# offer to clean the model before importing starts
		clear_all_maybe
		
		# Get the directory of the loaded file
		loaded_file_dir = File::dirname(file_data_path)
		# Change directory to the directory of the loaded file
		Dir::chdir(loaded_file_dir)
		model = Sketchup.active_model
		entities = model.entities
		@scale = 1.0
		pts = []
		drills_x = []
		drills_y = []
		error_package = []		# used to store the list of erroneous package, so they are displayed only once
		outline_edges = [] 		# used to store edges created for the outline / drilling
		auto_resize_yes = []	# list of parts with auto resize enabled by user
		auto_resize_nop = []	# list of parts with auto resize disabled by user
		
		# definition of the colors used for the board and for the plating
		default_board_color = Sketchup::Color.new(38,104,68) # 0x266844 - Green
		default_plating_color = Sketchup::Color.new(191,172,95)	# 0xbfac5f - Gold
		default_silk_color = Sketchup::Color.new("Ivory") # Ivory

		color_board = default_board_color
		color_tracing = default_board_color
		color_plating = default_plating_color
		color_silk = default_silk_color

		# The size limits of the board
		min_x = nil
		min_y = nil
		max_x = nil
		max_y = nil

		images_created = nil

		# log file open at the beginning in case we want to write during import
		file = File.open file_data_path , "r"
			puts "eagleUp > open file " + file_data_path
		log_file = File.new( file_data_path[0..-5] + ".log" ,  "w")

		
		# global variables
		decimal_separator = "."
		model_path = 		""
		convert_cmd = 		""
		composite_cmd = 	""
		rm_cmd = 			""
		threshold = 		0.001.to_f		# 1 mil
		scale_is_meters	= 	1
		image_prefix 	=	""
		result_extension=""		# used in various places
		
		# from now on the eup file is read and for each line an action is processed, like adding a package on the board
		file.each do |line|

			line=line.unpack("C*").pack("U*")	# UTF-8 fix
		
			# when using comma as decimal sign some errors can occur as the raw data is recorded with a dot
			# if the user defines comma in the settings, the dots are replaced by commas then the command is interpretated
			initial_line = String.new( line )
			if( decimal_separator == "," )
				line.gsub!(/\./,",")
			end

			# the array elements contain the various fields of each line
			elements = line.split(";")
			initial_elements = initial_line.split(";")
			
			case elements[0]
		
				when "settings"
					model_path = 		initial_elements[1]
					convert_cmd = 		"\""+initial_elements[2]+"\""
					composite_cmd = 	"\""+initial_elements[3]+"\""
					
					rm_cmd = 			initial_elements[4]
						puts "system > settings imported"
					
					# check for template settings, units and decimal sign
					length = 100.to_l		# 100 inch
					str_test = length.to_s	# 100 inch converted into user's units
					puts "system > testing units"
					puts "system >    100 inch = " + str_test
					if ( str_test[0,2]=="2." || str_test[0,2]=="2," )
						puts "system >     template meters ok"
						threshold = threshold * 1000
						scale_is_meters = 1
						if( str_test[1,1]=="." )
							decimal_separator = "."
							puts "system >     using dot as decimal separator"
						else
							decimal_separator = ","
							puts "system >     using comma as decimal separator"
						end
						
					elsif ( str_test[0,5]=="2540." || str_test[0,5]=="2540," )
						puts "system >     template millimeters ok"
						scale_is_meters = 0
						if( str_test[4,1]=="." )
							decimal_separator = "."
							puts "system >     using dot as decimal separator"
						else
							decimal_separator = ","
							puts "system >     using comma as decimal separator"
						end
					
					else
						puts "system >     error in template"
						UI.messagebox( "eagleUp has detected an error in the template. For best experience you need to set the template to engineering - meters in the preferences/template menu. After setting the template you need to restart Sketchup. eagleUp will now close." )
						return 0
					end
					
				when "outline-line"
					# Line element is a line
					begin
						# something potentially bad
						pts1 = [strToL(elements[1]), strToL(elements[2]), strToL(elements[5])/2]
					rescue Exception=>e
						# handle e
						UI.messagebox( "exception occured on outline-line" )
						return -1
					end
					
					pts2 = [strToL(elements[3]), strToL(elements[4]), strToL(elements[5])/2]
					outline_edges[outline_edges.length]=entities.add_line pts1, pts2

				when "outline-arc"
					# Line element is an arc
					begin
						# something potentially bad
						center = [strToL(elements[1]), strToL(elements[2]), strToL(elements[6])/2]
					rescue Exception=>e
						# handle e
						UI.messagebox( "exception occured on outline-arc" )
						return -1
					end
					
					# Create an arc perpendicular to the normal or Z axis
					vector = Geom::Vector3d.new 0,0,1
					vector2 = Geom::Vector3d.new 1,0,0
					vector3 = vector.normalize!
					# We only like one of the edges from the arc since the faces should be the same for all edges
					outline_edges[outline_edges.length] =
					(entities.add_arc center, vector2, vector3, strToL(elements[3]), elements[4].to_f.degrees, elements[5].to_f.degrees, 24)[0]

					
				when "outline"
					# Document outline, used to position the images
					min_x = strToL(elements[1])
					min_y = strToL(elements[2])
					max_x = strToL(elements[3])
					max_y = strToL(elements[4])
					
					# Since the face is created by multiple vectors we need to wait until the
					# outline has been fully described, the order of the lines in the exported
					# file is therefore of importance
				when "outline-complete"
					thickness = strToL(elements[1])

					# If no boarder lines have been defined use the outline for the board size
					if outline_edges.length <= 0
						# Create outline from max/min value
								# build the board considering the largest dimensions of the board          
						pts1 = [min_x, min_y, thickness/2]
						pts2 = [max_x,min_y, thickness/2]
						outline_edges[outline_edges.length]=entities.add_line pts1, pts2

						pts1 = [max_x, min_y, thickness/2]
						pts2 = [max_x,max_y, thickness/2]
						outline_edges[outline_edges.length]=entities.add_line pts1, pts2

						pts1 = [max_x, max_y, thickness/2]
						pts2 = [min_x,max_y, thickness/2]
						outline_edges[outline_edges.length]=entities.add_line pts1, pts2

						pts1 = [min_x, max_y, thickness/2]
						pts2 = [min_x,min_y, thickness/2]
						outline_edges[outline_edges.length]=entities.add_line pts1, pts2
					end

					# ensure that all edges are connected
					outline_edges.each do |edge1|
						outline_edges.each do |edge2|
							connect_close_vertices(entities, get_true_start_of_edge(edge1), get_true_end_of_edge(edge2), threshold)
							connect_close_vertices(entities, get_true_end_of_edge(edge1), get_true_end_of_edge(edge2), threshold)
							connect_close_vertices(entities, get_true_start_of_edge(edge1), get_true_start_of_edge(edge2), threshold)
						end
					end
					
					for edge in outline_edges
						edge.find_faces
					end

					faces = model.entities

					# Count the faces to find the board face, that will be the one which all lines are connected to
					board_face=0
					max_connected=0
					remove_faces = []

					faces.each do |entity|
						if entity.typename == "Face"
							connected = entity.edges.length
							if connected >= max_connected
								# Remove the old board face since it was incorrect
								if board_face != 0
									remove_faces[remove_faces.length]=board_face
								end
								board_face = entity
								max_connected = connected
							else
								remove_faces[remove_faces.length]=entity
							end
						end
					end

					# Remove the face that's not the board
					model.entities.erase_entities remove_faces

					if board_face != 0
						materials = model.materials
						mat_board = materials.add 'mat_board'
						mat_board.color = color_board

						top_mat = materials.add image_prefix + '_top_board'
						top_mat.color = color_board
						bottom_mat = materials.add image_prefix + '_bottom_board'
						bottom_mat.color = color_board
						
						if board_face.normal[2] < 0
							board_face.pushpull thickness, false
						else
							board_face.pushpull -thickness, false
						end

						# Assign the images to the board top and bottom faces
						if (images_created != nil && min_x != nil && min_y != nil && max_x != nil && max_y != nil)
							if( (top_mat.texture = image_prefix + "_board_top." + result_extension) != nil && top_mat.texture != nil)
								top_mat.texture.size = [max_x-min_x,max_y-min_y]
							end
							if( (bottom_mat.texture = image_prefix + "_board_bottom." + result_extension) != nil && bottom_mat.texture != nil)
								bottom_mat.texture.size = [max_x-min_x,max_y-min_y]
							end
						end


						# this section applies the board color on all faces for realistic view
						part = model.entities
						part.each do |ent|
							if ent.typename == "Face"
								
								# if face is on the x/y place we must have a top or bottom face
								# because of float values we need to check that the value is around 0
								if (ent.plane[0] <= 1E-30 && ent.plane[0] >= -1E-30 && ent.plane[1] <= 1E-30 && ent.plane[1] >= -1E-30)

									# if the face is at 0 on the z axis it will be the top face
									if (ent.normal[2] > 0)
										# Assign images function
										ent.material = top_mat
										on_front = true
										pos_array=[]
										pos_array[0] = [min_x,min_y,0] # Point 1 in model
										pos_array[1] = [0,0,0] # Point 1 on image

										ent.position_material top_mat, pos_array, on_front

										# If the face is at the bottom position it will be the bottom face
									else if(ent.normal[2] < 0)
										ent.material = bottom_mat
										on_front = true

										pos_array=[]
										# Point 1 in model have moved in z axis for the bottom
										pos_array[0] = [min_x,min_y,thickness]
										pos_array[1] = [0,0,0] # Point 1 on image
										ent.position_material bottom_mat, pos_array, on_front

									end
								end
							else
							
								ent.material = mat_board
							end
						end
					end
				end
					puts "outline > outline completed"

			
				when "color"
					# input file describes the color of the board and of the plating
					color_board		= newColor(elements[1],default_board_color)
					color_tracing	= newColor(elements[2],default_board_color)
					color_plating	= newColor(elements[3],default_plating_color)
					color_silk		= newColor(elements[4],default_silk_color)
						puts "color > colors set"
							
				when "images"
					if USE_RELATIVE_PATH == 1
						directory = ""
					else
						directory = initial_elements[1]
					end
					
					image_prefix = initial_elements[2]
					image_suffix = initial_elements[3]
					result_extension = initial_elements[5]

					# Produce the top and bottom images
						puts "images > creating top and bottom images"
					images_created = create_images(directory,image_prefix,image_suffix,color_board,color_tracing,color_plating,color_silk,convert_cmd,composite_cmd,rm_cmd,file_data_path,result_extension)
						puts "images > images created"
					
				when "hole"
					# this section drills the board
					if(@existing_faces == nil || @existing_faces.length <= 0)
						@existing_faces = faceArray(Sketchup.active_model.entities)
					end
					# check if a drill has already been processed in this location (break the rendering)
					drill_exist = 0
					drills_x.length.times do |i|
						if drills_x[i]==strToL(elements[1]) and drills_y[i]==strToL(elements[2])
							drill_exist = 1
						end
					end

					if drill_exist == 0

						# add the coordinates to the list of existing drills
						drills_x[drills_x.length] = strToL(elements[1])
						drills_y[drills_y.length] = strToL(elements[2])

						centerpoint = Geom::Point3d.new( strToL(elements[1]), strToL(elements[2]),
						strToL(elements[4]))
						# Create a circle perpendicular to the normal or Z axis
						vector = Geom::Vector3d.new 0,0,1
						vector2 = vector.normalize!
						model = Sketchup.active_model
						active_entities = model.active_entities
						edges = active_entities.add_circle centerpoint, vector2, strToL(elements[3]) , 12 # instead of 24 to reduce model complexity

						array_faces = edges[0].faces

						if(array_faces.length > 0)
							# check if the face has any edges which are not from the circle
							# that would indicate that it's not the hole face
							for fa in array_faces
								if((fa.edges-edges).length == 0)
									fa.pushpull(-2*strToL(elements[4]))
								end
							end
						end
					end

				when "hole-complete"
					if(@existing_faces != nil && @existing_faces.length > 0)
						# plating of the hole side
						new_faces = faceArray(model.entities) - @existing_faces

						materials = model.materials
						mat = materials.add elements[1]
						mat.color = newColor( elements[3] , 0x000000 )

						# Add plating color for holes
						for face in new_faces
							if face.typename == "Face"
								face.material = mat
							end
						end
					end

					# Reset known entities to enable new holes to be drilled
					@existing_faces = [];
					puts "holes > holes punched"
				
				when "package"
					if(elements.length >= 6 && initial_elements[6] != nil)

						begin
						
							comp_def = Sketchup.active_model.definitions.detect { |model| model.name == initial_elements[6] }
							comp_loc = Geom::Point3d.new strToL(elements[2]), strToL(elements[3]), strToL(elements[7])
							transf0 = Geom::Transformation.scaling (1)
							axis = Geom::Vector3d.new 0, 0, 1
								
							if comp_def.nil?
								entity_path = findModelOnDisk(initial_elements, model_path)
								if File::readable?(entity_path)
									comp_def = Sketchup.active_model.definitions.load(entity_path)
									puts "Loaded component " + comp_def.name + " from disk location " + entity_path
								end
							end
							
							# scale component to match model if necessary
							transf0 = scaleModel(comp_def, auto_resize_nop, auto_resize_yes, initial_elements, scale_is_meters)
							
							entities = Sketchup.active_model.active_entities
							instance = entities.add_instance comp_def, transf0
							
							transf1 = Geom::Transformation.new comp_loc
							entities.transform_entities(transf1, instance)
							
							# rotate new components if necessary
							if elements[4].to_f != 0
								transf2 = Geom::Transformation.rotation comp_loc, axis, (elements[4].to_f).degrees
								entities.transform_entities(transf2, instance)
							end

							# change side if bottom layer
							if elements[7].to_l < 0
								transf3 = Geom::Transformation.rotation comp_loc, Geom::Vector3d.new(1, 0, 0), 180.degrees
								entities.transform_entities(transf3, instance)
							end
							
						rescue NameError => e
							#puts "name error " + e.backtrace.inspect
							puts "not found " + initial_elements[6]
						rescue FileNotFoundException
							error_package.push(initial_elements[6])
						rescue Exception => e
							puts "caught an exception: " + (e.message)
							puts e.backtrace.inspect
						end
							
					else
						# Not a correct raw in the data file - ignore
					end

			end # end case
		
		end # end   file.each do |line|
		
		
		# after all lines have been checked...
		
		file.close
		puts "eagleUp > close file"
		
		view = Sketchup.active_model.active_view
		new_view = view.zoom_extents

		set_pcb_layers	# group pcb and parts into their layers
		
		# Show all the missing packages in the end together
		if error_package.length > 0
			msg = "Missing packages:"
			error_package.each do |missing|
				if missing != nil
					msg += "\n"
					msg += missing
				end
			end
			log_file.puts msg
			UI.messagebox( "Eagle'up import completed\n\n" + msg , MB_MULTILINE)
		else
			log_file.puts "every model correctly imported"
			UI.messagebox("Eagle'up import completed")
		end

		log_file.close
		puts "eagleUp > import completed"
		
		# Success
		return 0
	end # def
	
	def findModelOnDisk(initial_elements, model_path)
		Find.find(model_path) do |lookup_file|
			if FileTest.directory?(lookup_file)
				if File.basename(lookup_file)[0] == ?.
					Find.prune # Don't look any further into this directory.
				else
					next
				end
			else
				if File.basename(lookup_file) == initial_elements[6] + ".skp"
					return File.expand_path(lookup_file)
				end
			end
		end
		raise FileNotFoundException
	end
	
	def scaleModel(comp_def, auto_resize_nop, auto_resize_yes, initial_elements, scale_is_meters)
		auto_yes = 0
		auto_nop = 0
		model_scale = 1
		bbox = comp_def.bounds
		
		if scale_is_meters == 1
		
			if (bbox.depth<4.to_f && bbox.height<4.to_f && bbox.width<4.to_f) # limit = 0.100 meters (mm) ==  4 inch
				# search in auto_resize_yes and no
				auto_resize_yes.length.times do |i|
					if auto_resize_yes[i]==initial_elements[6]
						auto_yes = 1
						model_scale = 1000
						puts "auto resize"
					end
				end
				auto_resize_nop.length.times do |i|
					if auto_resize_nop[i]==initial_elements[6]
						auto_nop = 1
					end
				end
		
				if (auto_yes == 0 && auto_nop == 0)
					puts ("it seems that " + initial_elements[6] + " is quite small")
					answer = UI.messagebox("it seems that " + initial_elements[6] + " is quite small\nDo you want to resize it?", MB_YESNO)
					if answer == 6 # Yes
						model_scale = 1000
						auto_resize_yes[auto_resize_yes.length] = initial_elements[6]
					else
						auto_resize_nop[auto_resize_nop.length] = initial_elements[6]
					end
				end
			end
		else
			if (bbox.depth>4.to_f && bbox.height>4.to_f && bbox.width>4.to_f) # limit = 100 mm ==  4 inch
				# search in auto_resize_yes and no
				auto_resize_yes.length.times do |i|
					if auto_resize_yes[i]==initial_elements[6]
						auto_yes = 1
						model_scale = 0.001
						puts "auto resize"
					end
				end
				auto_resize_nop.length.times do |i|
					if auto_resize_nop[i]==initial_elements[6]
						auto_nop = 1
					end
				end
				if (auto_yes == 0 && auto_nop == 0)
					puts ("it seems that " + initial_elements[6] + " is quite large")
					answer = UI.messagebox("it seems that " + initial_elements[6] + " is quite large\nDo you want to resize it?", MB_YESNO)
					if answer == 6 # Yes
						model_scale = 0.001
						auto_resize_yes[auto_resize_yes.length] = initial_elements[6]
					else
						auto_resize_nop[auto_resize_nop.length] = initial_elements[6]
					end
				end
			end
		end
		Geom::Transformation.scaling (model_scale)
	end

	# Creates a new color or reverts to the defaults if it fails
	def newColor(str,default_color)
		color=default_color
		begin

		if(str[0,2] == "0x")
			red = str[2,2].hex
			green = str[4,2].hex
			blue = str[6,2].hex
			color = Sketchup::Color.new(red,green,blue)
		else
			color = Sketchup::Color.new(str)
		end

		if(color == nil)
			color = default_color
		end
		rescue
		color = default_color
		end
		return color
	end

	# Returns a RGB string formated as "#abcdef" from a color object
	def rgb_string(color)
		return sprintf("#%2.2X%2.2X%2.2X",color.red,color.green,color.blue);
	end


	def create_images(directory, prefix,image_suffix,color_board,color_tracing,color_plating,color_silk,convert_cmd,composite_cmd,rm_cmd,file_data_path,result_extension)
		image_prefix = directory + prefix
		
		# if we find raw files in the folder => create texture, then delete the raw file
		# on a second run, we find only the textures and use them directly
		if File.file?( image_prefix + "_top.png" )
			# raw file found
		else
			puts( "using directly the texture." )
			return 1
		end
		
		# Find board size
		crop_cmd = convert_cmd + " -trim \"" + image_prefix + "_imagesize.png\" -format \"%wx%h+%X+%Y\" info: >size.dat"
		%x[#{crop_cmd}]
		size_file = File.new("size.dat",  "r")	# issue with SU 2014 on some setups prevent reading back the cropping data, instead now using a temp file
		crop_arg = size_file.gets
		size_file.close
		
		# versions 6.7.7 of ImageMagick had issues with the output parameters. To solve it a + sign is forced in the string.
		# The following lines clean and trim the output.
		crop_arg.gsub!("+++","+")
		crop_arg.gsub!("++","+")
		crop_arg.gsub!("\n","")
		
		# top image
		top_cmds  = composite_cmd + ' -transparent-color "white" -compose plus ' + "\"" + image_prefix + "_top_mask.png\" " + "\"" + image_prefix + "_top.png\" pads.png\n"
		top_cmds += convert_cmd + " -negate \"" + image_prefix + "_top_mask.png\" maskn.png\n"
		top_cmds += composite_cmd + " -transparent-color \"white\" -compose plus \"" + image_prefix + "_top.png\" maskn.png  traces.png\n"
		cmds = top_cmds

		# create board
		board_color_cmds = convert_cmd + " \"" + image_prefix + "_imagesize.png\" " + ' -transparent "white"  -fill "' + rgb_string(color_board) + '" -colorize "100,100,100,0"  board.png' + "\n"
		cmds += board_color_cmds

		# set colors
		color_cmds  = convert_cmd + ' -transparent "white" -fill "' + rgb_string(color_plating) + '" -colorize "100,100,100,0" pads.png pads.png' + "\n"
		color_cmds += convert_cmd + ' -transparent "white"  -fill "' + rgb_string(color_tracing) + '" -colorize "100,100,100,0" traces.png traces.png' + "\n"
		
		cmds += color_cmds
		cmds += convert_cmd + " \"" + image_prefix + "_top_silk.png\" " + ' -transparent "white" -fill "' + rgb_string(color_silk) + '" -colorize "100,100,100,0" silk.png' + "\n"

		# create combined top image
		top_combine_cmds = convert_cmd + ' -flatten -background "none" ' + "board.png traces.png silk.png pads.png \"" + prefix + "_board_top.png\"\n"
		top_combine_cmds += convert_cmd + " \"" + prefix + "_board_top.png\" -crop \"" + crop_arg + "\" \"" + prefix + "_board_top." + result_extension + "\"\n"
		cmds += top_combine_cmds

		# bottom image
		bottom_cmds = composite_cmd + " -transparent-color \"white\" -compose plus \"" + image_prefix + "_bottom_mask.png\" \"" + image_prefix + "_bottom.png\" padsB.png\n"
		bottom_cmds += convert_cmd + " -negate \"" + image_prefix + "_bottom_mask.png\" masknB.png\n"
		bottom_cmds += composite_cmd + " -transparent-color \"white\" -compose plus \"" + image_prefix + "_bottom.png\" masknB.png tracesB.png\n"
		cmds += bottom_cmds

		# set colors
		color_cmds  = convert_cmd + ' -transparent "white" -fill "' + rgb_string(color_plating) + '" -colorize "100,100,100,0" padsB.png padsB.png' + "\n"
		color_cmds += convert_cmd + ' -transparent "white"  -fill "' + rgb_string(color_tracing) + '" -colorize "100,100,100,0" tracesB.png tracesB.png' + "\n"
		cmds += color_cmds
		cmds += convert_cmd + " \"" + image_prefix + "_bottom_silk.png\" " + ' -transparent "white" -fill "' + rgb_string(color_silk) + '" -colorize "100,100,100,0" silkB.png' + "\n"

		# create combined bottom image
		bottom_combine_cmds = convert_cmd + ' -flatten -background "none" ' + "board.png tracesB.png  silkB.png padsB.png \"" + prefix + "_board_bottom.png\"\n"
		bottom_combine_cmds += convert_cmd + " \"" + prefix + "_board_bottom.png\" -crop \"" + crop_arg + "\" -flop \"" + prefix + "_board_bottom." + result_extension + "\"\n"
		cmds += bottom_combine_cmds

		# remove temporary files
		rm_cmds = rm_cmd + " board.png pads.png padsB.png silk.png silkB.png maskn.png masknB.png traces.png tracesB.png size.dat " + image_prefix + "_top_mask.png " + image_prefix + "_top.png " + image_prefix + "_top_mask.png " + image_prefix + "_top_silk.png " + image_prefix + "_bottom_mask.png " + image_prefix + "_bottom.png " + image_prefix + "_bottom_silk.png " + image_prefix + "_outline.png " + image_prefix + "_imagesize.png " + "\n"
		if( result_extension == "jpg" )
			rm_cmds += rm_cmd + " \"" + prefix + "_board_top.png\"  \"" + prefix + "_board_bottom.png " 
		end
		cmds += rm_cmds

		# Run commands
		# Change to working directory
		if USE_RELATIVE_PATH == 0
			Dir.chdir(directory);
		end
		
		cmds.each_line do |line|
			%x[#{line}]	# change of system input/output syntax
		end
	end

end



# the module below is copied from Ruby version 1.9.2 (currently not supported in Sketchup default installation)
# find.rb: the Find module for processing all files under a given directory.
# The +Find+ module supports the top-down traversal of a set of file paths.
module Find
# Calls the associated block with the name of every file and directory listed
# as arguments, then recursively on their subdirectories, and so on.
# See the +Find+ module documentation for an example.
	def find(*paths) # :yield: path
		paths.collect!{|d| d.dup}
		while file = paths.shift
			catch(:prune) do
				yield file.dup.taint
					next unless File.exist? file
					begin
					if File.lstat(file).directory? then
						d = Dir.open(file)
						begin
							for f in d
								next if f == "." or f == ".."
								if File::ALT_SEPARATOR and file =~ /^(?:[\/\\]|[A-Za-z]:[\/\\]?)$/ then
									f = file + f
								elsif file == "/" then
									f = "/" + f
								else
									f = File.join(file, f)
								end
								paths.unshift f.untaint
							end
						ensure
							d.close
						end
					end
				rescue Errno::ENOENT, Errno::EACCES
				end
			end
		end
	end

	# Skips the current file or directory, restarting the loop with the next
	# entry. If the current file is a directory, that directory will not be
	# recursively entered. Meaningful only within the block associated with
	# Find::find.
	# See the +Find+ module documentation for an example.
	def prune
		throw :prune
	end

	module_function :find, :prune
end


def set_pcb_layers
	# change all components to parts layer unless they are pcb layer already. 
	# Set PCB to pcb layer and group it.
	# thanks Glenn
	
    # Establish necessary handles
    model = Sketchup.active_model
    ent=model.entities
    selection=model.selection
    
    pcb_layer = model.layers.add("pcb")     # Add pcb layer if it does not already exist
    parts_layer = model.layers.add("parts") # Add parts layer if it does not already exist
      
    # change all Components to parts layer unless it is a pcb layer
    ent.each{|x|
       x.layer = parts_layer if x.is_a? Sketchup::ComponentInstance unless x.layer === pcb_layer
      }
 
    parts_layer.visible = false 			# hide parts layer
    Sketchup.send_action("21101") 			# select everything

    t1=Time.now; UI.start_timer(1.0) {p Time.now-t1} #delay 1 second.  Seems to be necessary?
    
    # collect all the entities into ents
    ents = []
    for e in model.entities()
        ents.push( e ) if e.layer().visible?()
    end

    #add the visible entities to a group
    group = model.active_entities.add_group( ents )

    #name the group
    name = model.definitions.unique_name('pcbgroup')
    group.name = name

    #Reset (?) ent
    ent=model.entities
    

    # change everything to pcb layer if the layer encountered is not a parts layer (should be just one group)
    ent.each{|x|
        # change to pcb layer if the layer encountered is not a parts layer
        x.layer = pcb_layer unless x.layer === parts_layer 
      }
    parts_layer.visible = true # unhide parts layer

end


def clear_all_maybe()
	# Give operator the option to delete everything in the model.
	# thanks Glenn
	
    # Establish necessary handles
    model = Sketchup.active_model()
    ent=model.entities()
    selection=model.selection()
    
   	# Create and fill an array with all the entities in the model
	sel_ents = []
	for e in ent do
		sel_ents.push( e )
	end
	
	selection.add(sel_ents) # Select every entity in model.
	
	# if something is selected (there is something to select), then ask whether or not to erase them.
 	if selection.count > 0
 		# Answer a messagebox query 'yes' or 'no'.  If 'yes' (default), then erase everything.
 		result = UI.messagebox( "Your model is not empty. Do you want to clean it before running eagleUp importer (recommended) ?", MB_YESNO)

		# If answer was 'yes' then erase everything in model.
		if result == 6 # Yes
 			ent.erase_entities( sel_ents ) # erase all selections
			model.active_view.refresh		# force screen redraw to show the erase
		end

	end

end



def scale_model( ratio , iterations )
	model = Sketchup.active_model
	entities = model.active_entities	
	model.selection().clear()
	ents = []

	for en in model.entities()
		ents.push( en )
	end
	model.selection().add( ents )
	
	trans = Geom::Transformation.scaling( ratio )
	for iter in 1..iterations
		entities.transform_entities(trans, ents.to_a )
	end
	
	view = Sketchup.active_model.active_view
	new_view = view.zoom_extents
end




### plugin menus entries and submenu

plugins_menu = UI.menu("Plugins")

plugins_menu.add_item("Import eagleUp v4.5"){
	eagle_up = EagleUp.new.import()
}

submenu = plugins_menu.add_submenu("Scale")

submenu.add_item("Dimensions"){
	model = Sketchup.active_model
    model_bb = model.bounds
	UI.messagebox( model_bb.width.to_s + ' x ' + model_bb.depth.to_s + ' x ' + model_bb.height.to_s )
}

submenu.add_item("set units"){
	 status = UI.show_model_info "Units"
}

submenu.add_separator

submenu.add_item("Scale Down 10"){
	scale_model(0.1,1)
}

submenu.add_item("Scale Up 10"){
	scale_model(10,1)
}

submenu.add_separator

submenu.add_item("Scale down 1000"){
	scale_model(0.1,3)
}

submenu.add_item("Scale up 1000"){
	scale_model(10,3)
}


