#!/usr/bin/env ruby
require 'rexml/document'
require 'nokogiri'
require 'uuid'
include Nokogiri
## MagicDraw XMI export to Canonical XMI
## Version 0.1
## 2012-02-03
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
sw = "Canonical XMI generator for MagicDraw"
swv = "$Revision: 1.31 $"
swv = swv.split(' ')[1]
xmi_input_file = " "
debug = TRUE
for arg in ARGV
	argarray = arg.split('=')
	if argarray[0] == "xmi"
		xmi_input_file = argarray[1]
	end
	
	if argarray[0] == "help" or argarray[0] == "-help" or argarray[0] == "--help" or argarray[0] == "-h" or argarray[0] == "--h"
		puts "#{sw} Version #{swv}"
		puts " "
		puts "Usage parameters : xmi=<MD sysml.xmi>"
		puts " "
		puts "  <MD sysml.xmi> required input MagicDraw SysML XMI file"				
		exit
	end
end

if xmi_input_file == " "
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : No XMI input"
	puts "Usage parameters : xmi=<MD sysml.xmi>"
	exit
end
if FileTest.exist?(xmi_input_file) != true
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : XMI input file not found : #{xmi_input_file}"
	exit
end
##
##  Set up XMI File and template output file
##
stime = Time.now
puts 'START ' + stime.to_s

xmifile = File.new(xmi_input_file, "r")
inxml = Nokogiri::XML(xmifile)

xmi_elements = inxml.xpath('//xmi:XMI')
if xmi_elements.size == 0
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : File contains no 'xmi:XMI' XML elements :  #{xmi_input_file}, may not be XMI file."
	xmifile.close
	exit
end

uuid_elements = inxml.xpath('//*[@xmi:uuid]')
if uuid_elements.size == 0
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : File does not contain UUID's."
	puts "Export again after setting Options->Environment->General->Save/Load->Save UUID"
	xmifile.close
	exit
end

href_hash = Hash.new

#find the template
begin
	block = inxml.root.xpath('PLCS:Template').first
rescue
	puts "WARNING: File does not contain a template"
end
profile = false
indexfile = false
uuidfilename = "dvlp\\UUIDs.xml"
if !block.nil?
	startpoint = '..\\..\\'
	block_base = block["base_Class"].to_s.strip
	template = inxml.xpath('//packagedElement[@xmi:id="' + block_base + '"]').first
	templateName = template["name"].to_s.strip
	context = template.parent.parent.parent
	contextName = context["name"].to_s.strip
	xmi_output_file = templateName + ".xmi"
else 
	pkgDexs = inxml.xpath('//packagedElement[@xmi:type="uml:Package" and @name="DEXs"]')
	for dxpkg in pkgDexs
		innerPackages = dxpkg.xpath("./* [@name]") 
		# A DEX
		if innerPackages.size == 1
			startpoint = '..\\..\\'
			dex = innerPackages[0]
			dexName = dex["name"].to_s.strip
			context = dex.parent.parent.parent
			contextName = context["name"].to_s.strip
			xmi_output_file = dexName + ".xmi"
		end
	end
	if dex.nil?
	 # this looks like a profile or an index file!
		startpoint = ''
		profiles = inxml.xpath('//uml:Model//packagedElement[@xmi:type="uml:Profile" and not(@href)]')
		if profiles.size == 1
			profile = true
			#remove icon if present
			inxml.xpath('//icon').remove
			xmi_output_file = File.basename(xmi_input_file, File.extname(xmi_input_file)) + '.xmi'
		else
			templates = inxml.xpath('//packagedElement[@name="Templates"]').first
			if !templates.nil?
				indexfile = true
				context = templates.parent
				contextName = context["name"].to_s.strip
				xmi_output_file = "index.xmi"
			else
				xmi_output_file = File.basename(xmi_input_file, ".*")
				uuidfilename =  xmi_output_file+"_UUIDs.xml"
				xmi_output_file = xmi_output_file+'.xmi'
			end
		end
	end
end

path = File.expand_path File.dirname(xmi_input_file) 
Dir.chdir(path)

puts "Generating : " + xmi_output_file
href_hash["plcs_psm_module.mdxml"] = startpoint +'..\\..\\PLCS\\psm_model\\plcs_psm.xmi'

#find contexts and templates
pkgTmpls = inxml.xpath('//packagedElement[@xmi:type="uml:Package" and @name="Templates"]')
for pkgTmpl in pkgTmpls
	cntxName = pkgTmpl.parent["name"].to_s.strip
	tmpls = pkgTmpls.xpath('packagedElement[@xmi:type="uml:Package" and @href]')
	for tmpl in tmpls
		href = tmpl["href"].to_s
		hrefparts = href.split('.')
		tmplName = hrefparts[0].sub(cntxName,'')
		if (cntxName == contextName)
			if indexfile || (!dex.nil?)
				href_hash[cntxName + tmplName + ".mdxml"] = startpoint + 'templates\\' + tmplName + '\\' + tmplName + '.xmi'
			else
				href_hash[cntxName + tmplName + ".mdxml"] = '..\\' + tmplName + '\\' + tmplName + '.xmi'
			end
		else
			href_hash[cntxName + tmplName + ".mdxml"] = startpoint + '..\\' + cntxName + '\\templates\\' + tmplName + '\\' + tmplName + '.xmi'
		end
	end
end

#find dexs
pkgDexs = inxml.xpath('//packagedElement[@xmi:type="uml:Package" and @name="DEXs"]')
for pkgDex in pkgDexs
	cntxName = pkgDex.parent["name"].to_s.strip
	dxs = pkgDexs.xpath('packagedElement[@xmi:type="uml:Package" and @href]')
	for dx in dxs
		href = dx["href"].to_s
		hrefparts = href.split('.')
		dxName = hrefparts[0].sub(cntxName,'')
		dxName.sub!('DEXPlcsRep','')
		if (cntxName == contextName)
			if indexfile
				href_hash[hrefparts[0] + ".mdxml"] = startpoint + 'dexs\\' + dxName + '\\' + dxName + '.xmi'
			else
				href_hash[hrefparts[0] + ".mdxml"] = '..\\' + dxName + '\\' + dxName + '.xmi'
			end
		else
			href_hash[hrefparts[0] + ".mdxml"] = startpoint + '..\\' + cntxName + '\\dexs\\' + dxName + '\\' + dxName + '.xmi'
		end
	end
end

#find local profiles
profiles = inxml.xpath('//packagedElement[@xmi:type="uml:Profile" and @href and not(starts-with(@href, "http:"))]')
for profile in profiles
	href = profile["href"]
	hrefparts = href.split('.')
	href_hash[hrefparts[0] + ".mdxml"] = startpoint + '..\\' + hrefparts[0] + '.xmi'
end

def inExtension(node)
	while !node.parent.nil? do
		if node.name == "Extension"
				return true
		else
			if node == node.document.root
				return false
			end
		end
		node = node.parent
	end
end

for xml_node in inxml.xpath('//*' )
	href_node = xml_node["href"]
	if !href_node.nil?
		href = href_node.to_s
		hrefparts = href.split('#')
		path = hrefparts[0]
		newpath = href_hash[path]
		if newpath.nil?
			#need to try and find the path from Module information
			case path
				when 'http://www.omg.org/spec/SysML/20100301/SysML-profile.uml', 'http://www.omg.org/spec/SysML/20150709/SysML.xmi', 'UML_Standard_Profile.xml', 
				         'MD_customization_for_SysML.mdzip', 'Matrix_Templates_Profile.xml'
					href_hash[path] = path
					newpath = path
				else
					if xml_node.name == "propertyPath"
						newpath = ''
					else
						if inExtension(xml_node)
							newpath = ''
						end
					end
			end
		end
		if newpath.nil?
			#unresolved href
			puts 'Removed node with unresolved href: ' + href
			xml_node.remove
		else
			xml_node["href"] = newpath + "#" + hrefparts[1]
		end
	end	
end

#correct L2 stereotype names generated by MD
l2Stereos = inxml.xpath('//StandardProfileL2:*')
for l2Stereo in l2Stereos
	l2Stereo.name = l2Stereo.name.capitalize
end

#generate the image map file
if !template.nil?
	imagexml = Nokogiri::XML::Builder.new { |b| b.diagrams }.doc
	imagexml['context'] = contextName
	imagexml['template'] = templateName
	diagrams = inxml.xpath('//mdElement[@elementClass="Diagram"]')
	for diagram in diagrams
		diagramNode = Nokogiri::XML::Node.new("diagram", imagexml)
		imagexml.root.add_child diagramNode
		diagramNode["image"] = diagram['name']+'.png'
		diagramNode["type"] = diagram.xpath('.//type').first.text
		components = diagram.xpath('./mdElement/mdOwnedViews/mdElement')
		for component in components
			compNode = nil
			case component['elementClass']
				when 'Class'
					#need to work out what type of class			
					xmiidref = component.xpath('elementID').first.attributes()['idref']
					if !xmiidref.nil?
						stereotypeNode = inxml.xpath('//*[@base_Class="' + xmiidref + '"]').first
						if !stereotypeNode.nil?
							case stereotypeNode.name
								when 'Auxiliary'
								compNode = Nokogiri::XML::Node.new("block", imagexml)
								when 'Block'
								compNode = Nokogiri::XML::Node.new("block", imagexml)
								when 'ConstraintBlock'
								compNode = Nokogiri::XML::Node.new("constraintBlock", imagexml)
								when 'Template'
								compNode = Nokogiri::XML::Node.new("template", imagexml)
							end
							classNode = inxml.xpath('//packagedElement[@xmi:id="' + xmiidref + '"]').first
							compNode['name'] = classNode['name'].to_s
						end
					else
						href = component.xpath('elementID').first['href']
						if !href.nil?
							#assume this is a template!
							compNode = Nokogiri::XML::Node.new("template", imagexml)
							refExt = component.xpath('elementID/xmi:Extension/referenceExtension').first
							if !refExt.nil?
								refPath = refExt['referentPath']
								compNode['name'] = refPath.split('::').last
							end
							compNode['href'] = href.to_s
						end
					end
				when 'Part'
					compNode = Nokogiri::XML::Node.new("part", imagexml)
					xmiidref = component.xpath('elementID').first.attributes()['idref']
					if !xmiidref.nil?
						partNode = inxml.xpath('//ownedAttribute[@xmi:id="' + xmiidref + '"]').first
						if !partNode.nil?
							compNode['name'] = partNode['name'].to_s
							compType = partNode.xpath('type').first
							if compType.nil?
								typeId = partNode.attributes()['type']
								compType = inxml.xpath('//packagedElement[@xmi:id="' + typeId + '"]').first
								compNode['type'] = compType['name'].to_s
							else
								compNode['href'] = compType['href'].to_s
							end
						end
					else
						href = component.xpath('elementID').first['href']
						if !href.nil?
							refExt = component.xpath('elementID/xmi:Extension/referenceExtension').first
							if !refExt.nil?
								refPath = refExt['referentPath']
								compNode['name'] = refPath.split('::').last
							end
							compNode['href'] = href.to_s
						end
					end
				when 'InstanceSpecification'
					compNode = Nokogiri::XML::Node.new("instance", imagexml)
					xmiidref = component.xpath('elementID').first.attributes()['idref']
					if !xmiidref.nil?
						instanceNode = inxml.xpath('//packagedElement[@xmi:id="' + xmiidref.to_s + '"]').first
						if !instanceNode.nil?
							compNode['name'] = instanceNode['name'].to_s
							compNode['href'] = instanceNode.xpath('classifier').first['href'].to_s
						end
					else
						href = component.xpath('elementID').first['href']
						if !href.nil?
							refExt = component.xpath('elementID/xmi:Extension/referenceExtension').first
							if !refExt.nil?
								refPath = refExt['referentPath']
								compNode['name'] = refPath.split('::').last
							end
							compNode['href'] = href.to_s
						end
					end
			end
			
			if !compNode.nil?
				geometry = component.xpath("geometry").first.text
				areaNode = Nokogiri::XML::Node.new('area', imagexml)
				areaNode['shape'] = "rect" 
				geom = geometry.split(',')
				areaNode['left'] = geom[0].strip.to_s
				areaNode['top'] = geom[1].strip.to_s
				areaNode['right'] = (geom[0].to_i + geom[2].to_i).to_s
				areaNode['bottom'] = (geom[1].to_i + geom[3].to_i).to_s
				compNode.add_child areaNode
				diagramNode.add_child compNode
			end
		end
	end
	File.open("imagemap.xml","w"){|file| imagexml.write_xml_to file} 
	puts ""
	puts "Please commit the imagemap.xml file"
end

#delete extensions
inxml.xpath('//xmi:Extension').remove

#delete unknown namespace prefixed elements
xmi_elements[0].namespaces.each { |key, value|
	case key
		when "xmlns:xmi", "xmlns:uml", "xmlns:sysml", "xmlns:StandardProfile", "xmlns:StandardProfileL2", "xmlns:PLCS", "xmi:version"
		else
			keyparts = key.split(':')
			if keyparts[0] == "xmlns"
				inxml.xpath('//' + keyparts[1] + ':*').remove
			end
	end
}

#remove MD packages
model = inxml.xpath('//uml:Model')[0]
model.xpath('//packagedElement[@xmi:type="uml:Package" and @href="UML_Standard_Profile.xml#magicdraw_uml_standard_profile_v_0001"]').remove
model.xpath('//packagedElement[@xmi:type="uml:Package" and starts-with(@href,"MD_customization_for_SysML.mdzip")]').remove
model.xpath('//packagedElement[@xmi:type="uml:Profile" and starts-with(@href,"Matrix_Templates_Profile.xml")]').remove

#reset the Documentation fields
documentation = inxml.xpath('//xmi:Documentation')[0]
documentation["exporter"] = sw
documentation["exporterVersion"] = swv

#add profile applications if not present
if !context.nil?
	uuid = UUID.new
	appliedProfiles = inxml.xpath('//appliedProfile')
	containedProfiles = inxml.xpath('//packagedElement[@xmi:type="uml:Profile"]')
	for profile in containedProfiles
		profileApplication = appliedProfiles.select {|x| x["href"] == profile["href"]}
		if profileApplication.size == 0
			profileApplication = Nokogiri::XML::Node.new("profileApplication", inxml)
			profileApplication["xmi:type"] = "uml:ProfileApplication"
			profileApplication["xmi:uuid"] = uuid.generate
			context.add_child profileApplication
			profileApplication.namespace = nil
			appliedProfile = Nokogiri::XML::Node.new("appliedProfile", inxml)
			appliedProfile["xmi:type"] = "uml:Profile"
			appliedProfile["href"] = profile["href"]
			profileApplication.add_child appliedProfile
		end
	end
end

File.open(xmi_output_file,"w"){|file| inxml.write_xml_to file} 

puts ""
puts "Please commit the " + uuidfilename + " file"

#MagicDraw maintains both UUID's and ID's
# this code should ensure the UUID and ID pairs are recorded if changed
#save UUIDs
uuid_elements = inxml.xpath('//*[@xmi:uuid and @xmi:id]')
if File.exists?(uuidfilename)
	uuidfile = File.open(uuidfilename)
	uuidxml = Nokogiri::XML(uuidfile, &:noblanks)
	uuidfile.close
else
	uuidxml = Nokogiri::XML::Builder.new { |b| b.uuids }.doc
end	

for uuid_element in uuid_elements
	id = uuid_element.attributes()["id"]
	uuid = uuid_element.attributes()["uuid"]
	uuidmaps = uuidxml.xpath('//uuidmap[@id="' + id + '"]')
	#create a new node if the current pair does not exist
	oldmaps = uuidmaps.select {|x| x["uuid"] != uuid}
	if oldmaps.size == uuidmaps.size
		uuidmap = Nokogiri::XML::Node.new("uuidmap", uuidxml)
		uuidmap['id'] = id
		uuidmap['uuid'] = uuid
		uuidxml.root.add_child uuidmap
	end
	#delete any old pairs
	for uuidmap in oldmaps
		uuidmap.remove
	end
end

File.open(uuidfilename,"w"){|file| uuidxml.write_xml_to file} 

#delete unknown namespaces
# Have to use REXML since Nokogiri too pedantic about namespaces!
xmifile = File.new(xmi_output_file, "r")
inxml = REXML::Document.new(xmifile)
xmifile.close

xmi_elements = inxml.elements.to_a("//xmi:XMI")
xmi_elements[0].attributes.each { |key, value|
	case key
		when "xmlns:xmi", "xmlns:uml", "xmlns:sysml", "xmlns:StandardProfile", "xmlns:StandardProfileL2", "xmi:version"
		else
			xmi_elements[0].attributes.delete key
	end
}
#now add our profile namespace back in if required
if !context.nil?
	xmi_elements[0].add_attribute('xmlns:PLCS', 'http:///schemas/PLCS-profile.xmi')
end

inxml << REXML::XMLDecl.default
formatter = REXML::Formatters::Pretty.new 
formatter.compact = true 
File.open(xmi_output_file,"w"){|file| file.puts formatter.write(inxml.root,"")} 

stime = Time.now
puts 'END ' + stime.to_s
