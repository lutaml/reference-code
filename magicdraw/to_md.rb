#!/usr/bin/env ruby
require 'nokogiri'
require 'uuid'
include Nokogiri
## Canonical XMI to MagicDraw XMI module (MagicDraw < 1.8)
## Version 0.1
## 2012-01-30
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
sw = "MagicDraw module generator"
swv = "$Revision: 1.14 $"
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
		puts "Usage parameters : xmi=<sysml.xmi>"
		puts " "
		puts "  <sysml.xmi> required input SysML XMI file"
		exit
	end
end
if xmi_input_file == " "
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : No XMI input"
	puts "Usage parameters : xmi=<sysml.xmi>"
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
inxml = Nokogiri::XML(xmifile,&:noblanks)

xmi_elements = inxml.xpath("//xmi:XMI")
if xmi_elements.size == 0
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : File contains no 'xmi:XMI' XML elements :  #{xmi_input_file}, may not be XMI file."
	xmifile.close
	exit
end

href_hash = Hash.new

#setup xmi namespace
xmiNS = inxml.root.namespace_definitions.find{|ns| ns.prefix=="xmi"}

#find the what type of file we are dealing with
plcsNS = inxml.root.namespaces["xmlns:PLCS"]
if plcsNS != nil
	block = inxml.root.xpath('PLCS:Template').first
else
	block = nil
end

sharedPackage = nil

uuidfilename = "dvlp\\UUIDs.xml"
if block != nil
	block_base = block["base_Class"].to_s.strip
	template = inxml.xpath('//packagedElement[@xmi:id="' + block_base + '"]').first
	templateName = template["name"].to_s.strip
	context = template.parent.parent.parent
	contextName = context["name"].to_s.strip
	sharedPackage = template.parent
	sharedContext = contextName +'::Templates::' + templateName
	xmi_output_file = "dvlp\\" + contextName + templateName + ".mdxml"
else
	templates = inxml.xpath('//packagedElement[@name="Templates"]').first
	if templates != nil
		context = templates.parent
		contextName = context["name"].to_s.strip
		xmi_output_file = "dvlp\\index.mdxml"
	else
		input_parts = xmi_input_file.split("\\")
		input_filename = input_parts[input_parts.size - 1]
		sharedPackage = inxml.xpath('//packagedElement[@name="SysMLfromEXPRESS"]').first
		sharedContext = '::SysMLfromEXPRESS'
		if input_filename == "plcs_psm.xmi"
			xmi_output_file = "dvlp\\plcs_psm_module.mdxml"
		else
			file_parts = input_filename.split(".")
			xmi_output_file = file_parts[0] + ".mdxml"
			uuidfilename = file_parts[0] + "_UUIDs.xml"
		end
	end
end

path = File.expand_path File.dirname(xmi_input_file)
Dir.chdir(path)

puts "Generating : " + xmi_output_file

for xml_node in inxml.xpath( '//*' )
	href_node = xml_node["href"]
	if href_node != nil
		href = href_node.to_s
		hrefparts = href.split('#')
		path = hrefparts[0]
		newpath = href_hash[path]
		if newpath == nil
			if path.size > 0
				path_parts = path.split('\\')
				case path_parts.size
					when 1
						# A URI
						newpath = path
					when 2
					 # profile from index
						if path_parts[1] == "PLCS-profile.xmi"
						 newpath = "PLCS-profile.mdxml"
						 href_hash[path] = newpath
						else
							puts "Unknown href: " + href
						end
					when 3
						# Template in same context
						newpath = contextName + path_parts[1] + ".mdxml"
						href_hash[path] = newpath
					when 4
					 # profile
						if path_parts[3] == "PLCS-profile.xmi"
						 newpath = "PLCS-profile.mdxml"
						 href_hash[path] = newpath
						else
							puts "Unknown href: " + href
						end
					when 5
						if path_parts[4] == "plcs_psm.xmi"
							# PLCS_PSM reference!
							newpath = "plcs_psm_module.mdxml"
							href_hash[path] = newpath
						else
							# Template in another context from index
							newpath = path_parts[1] + path_parts[3] + ".mdxml"
							href_hash[path] = newpath
						end
					when 7
						if path_parts[6] == "plcs_psm.xmi"
							# PLCS_PSM reference!
							newpath = "plcs_psm_module.mdxml"
							href_hash[path] = newpath
						else
							# Template in another context
							newpath = path_parts[3] + path_parts[5] + ".mdxml"
							href_hash[path] = newpath
						end
					else
						puts "Unknown path: " + path.to_s
				end
			else
				# just an id!
				newpath = ""
			end
		end
		xml_node["href"] = newpath + "#" + hrefparts[1]
	end
end

model = inxml.xpath( '//uml:Model')[0]
#Add mount & share tables
doc = inxml.xpath( '//xmi:Documentation')[0]
if doc == nil
	doc = Nokogiri::XML::Node.new('Documentation', inxml)
	doc.namespace = xmiNS
	model.add_previous_sibling doc
end
doc['exporter'] = 'MagicDraw UML'
doc['exporterVersion'] = '17.0'

mainextension = Nokogiri::XML::Node.new('Extension', inxml)
mainextension.namespace = xmiNS
mainextension['extender'] = 'MagicDraw UML 17.0'
model.add_previous_sibling mainextension

plugin = Nokogiri::XML::Node.new('plugin', inxml)
plugin['pluginName']= 'SysML'
plugin['pluginVersion']= '17.0 sp4'
mainextension.add_child plugin
plugin.namespace = nil

if sharedPackage != nil
	shareTable = Nokogiri::XML::Node.new('shareTable', inxml)
	shareTable['shareVersion']= '-1'
	shareTable['standardSystemProfile'] = 'false'
	mainextension.add_child shareTable
	shareTable.namespace = nil

	share = Nokogiri::XML::Node.new('share', inxml)
	share['sharedPackage'] = sharedPackage.attributes["id"].to_s.strip
	shareTable.add_child share

	#Add SharedPackage as Module
	extension = Nokogiri::XML::Node.new('Extension', inxml)
	extension.namespace = xmiNS
	extension['extender'] = 'MagicDraw UML 17.0'
	sharedPackage.children.first.add_previous_sibling extension
	moduleExt = Nokogiri::XML::Node.new('moduleExtension', inxml)
	moduleExt['moduleRoot'] = sharedContext
	extension.add_child moduleExt
	moduleExt.namespace = nil
end

mountTable = Nokogiri::XML::Node.new('mountTable', inxml)
mainextension.add_child mountTable
mountTable.namespace = nil

moduleElem = Nokogiri::XML::Node.new('module', inxml)
moduleElem['resource'] = 'file:/C:/Program%20Files/MagicDraw%20UML/profiles/MD_customization_for_SysML.mdzip'
moduleElem['autoloadType'] = 'ALWAYS_LOAD'
moduleElem['readOnly'] = 'true'
moduleElem['loadIndex'] = 'true'
moduleElem['requiredVersion'] = '-1'
moduleElem['version'] = '17.0'
mountTable.add_child moduleElem

mount = Nokogiri::XML::Node.new('mount', inxml)
mount['mountPoint'] = '_12_0EAPbeta_be00301_1156851270584_552173_1'
mount['mountedOn'] = model.attributes["id"].to_s.strip
moduleElem.add_child mount

mount = Nokogiri::XML::Node.new('mount', inxml)
mount['mountPoint'] = '_16_8beta_2104050f_1262918510515_114803_6875'
mount['mountedOn'] = model.attributes["id"].to_s.strip
moduleElem.add_child mount

# add mounts for imported packages
href_hash.each do |path, filename|
	path_parts = path.split('\\')
	path_parts[path_parts.size - 1] = "dvlp"
	path_parts[path_parts.size] = filename
	fullpath = File.absolute_path path_parts.join('\\')
	fullpath.gsub!(' ','%20')
	fullpath = 'file:/' + fullpath

	moduleElem = Nokogiri::XML::Node.new('module', inxml)
  moduleElem['resource'] = fullpath
	moduleElem['autoloadType'] = 'ALWAYS_LOAD'
	moduleElem['readOnly'] = 'true'
	moduleElem['loadIndex'] = 'true'
	moduleElem['requiredVersion'] = '-1'
	mountTable.add_child moduleElem

	pkg = inxml.xpath( '//packagedElement[@xmi:type="uml:Package" and starts-with(@href,"' + filename + '")]')[0]
	if pkg == nil
		pkg = inxml.xpath( '//packagedElement[@xmi:type="uml:Profile" and starts-with(@href,"' + filename + '")]')[0]
	end

	href = pkg["href"].to_s.strip
	href_parts = href.split('#')
	mount = Nokogiri::XML::Node.new('mount', inxml)
	mount['mountPoint'] = href_parts[1]
	mount['mountedOn'] = pkg.parent.attributes["id"].to_s.strip
	moduleElem.add_child mount
end

#Add filepath properties
extension = Nokogiri::XML::Node.new('Extension', inxml)
extension.namespace = xmiNS
extension['extender'] = 'MagicDraw UML 17.0'
model.add_next_sibling extension
options = Nokogiri::XML::Node.new('options', inxml)
extension.add_child options
options.namespace = nil
styleMan = Nokogiri::XML::Node.new('mdElement', inxml)
styleMan['elementClass'] = 'StyleManager'
options.add_child styleMan
simpleStyle = Nokogiri::XML::Node.new('mdElement', inxml)
simpleStyle['elementClass'] = 'SimpleStyle'
styleMan.add_child simpleStyle
ssName = Nokogiri::XML::Node.new('name',inxml)
simpleStyle.add_child ssName
ssName.content = 'STYLE_USER_PROPERTIES'
ssdefault = Nokogiri::XML::Node.new('default', inxml)
ssdefault['xmi:value'] = 'false'
simpleStyle.add_child ssdefault
propManager = Nokogiri::XML::Node.new('mdElement', inxml)
propManager['elementClass'] = 'PropertyManager'
simpleStyle.add_child propManager
pmName = Nokogiri::XML::Node.new('name',inxml)
pmName.content = 'PROJECT_GENERAL_PROPERTIES'
propManager.add_child pmName
pmID = Nokogiri::XML::Node.new('propertyManagerID',inxml)
pmID.content = '_17_0_3_2b2015d_1328197428620_426689_11177'
propManager.add_child pmID
classPathList = Nokogiri::XML::Node.new('mdElement',inxml)
classPathList['elementClass'] = 'ClassPathListProperty'
propManager.add_child classPathList
cplID = Nokogiri::XML::Node.new('propertyID',inxml)
cplID.content = 'MODULES_DIRS'
classPathList.add_child cplID
cplDesc = Nokogiri::XML::Node.new('propertyDescriptionID',inxml)
cplDesc.content = 'MODULES_DIRS_DESCRIPTION'
classPathList.add_child cplDesc

#profiles
fileProperty = Nokogiri::XML::Node.new('mdElement', inxml)
fileProperty['elementClass'] = 'FileProperty'
classPathList.add_child fileProperty
fpVal = Nokogiri::XML::Node.new('value',inxml)
fpVal.content = '<install.root>\profiles'
fileProperty.add_child fpVal
selMode = Nokogiri::XML::Node.new('selectionMode',inxml)
selMode['xmi:value'] = '0'
fileProperty.add_child selMode
dispFP = Nokogiri::XML::Node.new('displayFullPath',inxml)
dispFP['xmi:value'] = 'true'
fileProperty.add_child dispFP
useFP = Nokogiri::XML::Node.new('useFilePreviewer', inxml)
useFP['xmi:value'] = 'false'
fileProperty.add_child useFP
dispAF = Nokogiri::XML::Node.new('displayAllFiles',inxml)
dispAF['xmi:value'] = 'true'
fileProperty.add_child dispAF
fpType = Nokogiri::XML::Node.new('fileType',inxml)
fpType.content = 'FILE_TYPE_ANY'
fileProperty.add_child fpType

#model libraries
fileProperty = Nokogiri::XML::Node.new('mdElement', inxml)
fileProperty['elementClass'] = 'FileProperty'
classPathList.add_child fileProperty
fpVal = Nokogiri::XML::Node.new('value',inxml)
fpVal.content = '<install.root>\modelLibraries'
fileProperty.add_child fpVal
selMode = Nokogiri::XML::Node.new('selectionMode',inxml)
selMode['xmi:value'] = '0'
fileProperty.add_child selMode
dispFP = Nokogiri::XML::Node.new('displayFullPath',inxml)
dispFP['xmi:value'] = 'true'
fileProperty.add_child dispFP
useFP = Nokogiri::XML::Node.new('useFilePreviewer', inxml)
useFP['xmi:value'] = 'false'
fileProperty.add_child useFP
dispAF = Nokogiri::XML::Node.new('displayAllFiles',inxml)
dispAF['xmi:value'] = 'true'
fileProperty.add_child dispAF
fpType = Nokogiri::XML::Node.new('fileType',inxml)
fpType.content = 'FILE_TYPE_ANY'
fileProperty.add_child fpType

href_hash.each do |key, path|
	fileProperty = Nokogiri::XML::Node.new('mdElement', inxml)
	fileProperty['elementClass'] = 'FileProperty'
	classPathList.add_child fileProperty
	fpVal = Nokogiri::XML::Node.new('value',inxml)
	key_parts = key.split('\\')
	case key_parts.size
		when 2
			fpVal.content = '<PLCSlib.data>\\contexts\\dvlp'
		when 3
			fpVal.content = '<PLCSlib.data>\\contexts\\' + contextName + '\\templates\\' + key_parts[1] +'\\dvlp'
		when 4
			fpVal.content = '<PLCSlib.data>\\contexts\\dvlp'
		when 5
			if path == "plcs_psm_module.mdxml"
				fpVal.content = '<PLCSlib.data>\\PLCS\\psm_model\\dvlp'
			else
				fpVal.content = '<PLCSlib.data>\\contexts\\' + key_parts[1] + '\\templates\\' + key_parts[3] +'\\dvlp'
			end
		when 7
			fpVal.content = '<PLCSlib.data>\\PLCS\\psm_model\\dvlp'
	end
	fileProperty.add_child fpVal
	selMode = Nokogiri::XML::Node.new('selectionMode',inxml)
	selMode['xmi:value'] = '0'
	fileProperty.add_child selMode
	dispFP = Nokogiri::XML::Node.new('displayFullPath',inxml)
	dispFP['xmi:value'] = 'true'
	fileProperty.add_child dispFP
	useFP = Nokogiri::XML::Node.new('useFilePreviewer', inxml)
	useFP['xmi:value'] = 'false'
	fileProperty.add_child useFP
	dispAF = Nokogiri::XML::Node.new('displayAllFiles',inxml)
	dispAF['xmi:value'] = 'true'
	fileProperty.add_child dispAF
	fpType = Nokogiri::XML::Node.new('fileType',inxml)
	fpType.content = 'FILE_TYPE_ANY'
	fileProperty.add_child fpType
end

moduleID = Nokogiri::XML::Node.new('moduleID',inxml)
moduleID.content = xmi_output_file
extension.add_child moduleID
moduleID.namespace = nil

#sort out appiedProfile if defined
for appliedProfile in inxml.xpath('//appliedProfile')
	extension = Nokogiri::XML::Node.new('Extension', inxml)
	extension.namespace = xmiNS
	extension['extender'] = 'MagicDraw UML 17.0'
	puts appliedProfile["href"]
	refExt = Nokogiri::XML::Node.new('referenceExtension', inxml)
	href = appliedProfile["href"]
	if href =="http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
		refPath = 'SysML'
	else
		hrefparts = href.split('#')
		if hrefparts[0] == "PLCS-profile.mdxml"
			refPath = 'PLCS'
		else
			puts "Unknown profile: " + href
		end
	end
	if template == nil
		if (context == nil) || (refPath== 'PLCS')
			appliedProfile.add_child extension
		else
			appliedProfile.parent.remove
		end
	else
		appliedProfile.parent.remove
	end
	refExt['referentPath'] = refPath
	refExt['referentType'] = 'Profile'
	extension.add_child refExt
	refExt.namespace = nil
	proExtension = extension.dup

	profile = inxml.xpath( '//packagedElement[@xmi:type="uml:Profile" and @href="' + href + '"]')[0]
	if profile == nil
		profile = Nokogiri::XML::Node.new('packagedElement', inxml)
		profile['xmi:type'] = 'uml:Profile'
		profile['href'] = href
		model.add_child profile
		profile.namespace = nil
	end

	profile.add_child proExtension
	# remove xmi namespace
	refExt = inxml.xpath('//xmi:referenceExtension').first
	refExt.namespace = nil
end

if File.exists?(uuidfilename)
	uuidfile = File.open(uuidfilename)
	$uuidxml = Nokogiri::XML(uuidfile, &:noblanks)
	uuidfile.close
else
	$uuidxml = Nokogiri::XML::Builder.new { |b| b.uuids }.doc
end

$uuid = UUID.new

def get_uuid(id)
	uuidmap = $uuidxml.xpath('//uuidmap[@id="' + id + '"]').first
	if uuidmap != nil
		return uuidmap.attributes["uuid"].to_s.strip
	else
		theUUID = $uuid.generate
		uuidtext = theUUID.to_s.strip
		uuidmap = Nokogiri::XML::Node.new("uuidmap", $uuidxml)
		uuidmap['id'] = id
		uuidmap['uuid'] = theUUID
		$uuidxml.root.add_child uuidmap
		return theUUID
	end
end

#add the default multiplicities and
# MD specific property stereotypes to attributes
props = inxml.xpath('//ownedAttribute [@xmi:type="uml:Property" or @xmi:type="uml:Port"]')
#need to add the namespace (nokogiri complains otherwise)
mdStereos = inxml.root.add_namespace_definition('additional_stereotypes','http://www.magicdraw.com/schemas/additional_stereotypes.xmi')
for prop in props
	if prop.at('lowerValue') == nil
		extension = Nokogiri::XML::Node.new('Extension', inxml)
		extension.namespace = xmiNS
		extension['extender'] = 'MagicDraw UML 17.0'
		prop.add_child extension
		modExt = Nokogiri::XML::Node.new('modelExtension', inxml)
		extension.add_child modExt
		modExt.namespace = nil
		lv = Nokogiri::XML::Node.new('lowerValue', inxml)
		lv['type'] = 'uml:LiteralInteger'
		id = prop.attributes()['id'].to_s + '-lowerValue'
		lv['id'] = id
		lv['uuid'] = get_uuid(id)
		lv['value'] = '1'
		modExt.add_child lv
		elemAttrs = lv.attributes
		elemAttrs['type'].namespace = xmiNS
		elemAttrs['id'].namespace = xmiNS
		elemAttrs['uuid'].namespace = xmiNS
	end

	if prop.at('upperValue') == nil
		extension = Nokogiri::XML::Node.new('Extension', inxml)
		extension.namespace = xmiNS
		extension['extender'] = 'MagicDraw UML 17.0'
		prop.add_child extension
		modExt = Nokogiri::XML::Node.new('modelExtension', inxml)
		extension.add_child modExt
		modExt.namespace = nil
		uv = Nokogiri::XML::Node.new('upperValue', inxml)
		uv['type'] = 'uml:LiteralUnlimitedNatural'
		id = prop.attributes()['id'].to_s + '-upperValue'
		uv['id'] = id
		uv['uuid'] = get_uuid(id)
		uv['value'] = '1'
		modExt.add_child uv
		elemAttrs = uv.attributes
		elemAttrs['type'].namespace = xmiNS
		elemAttrs['id'].namespace = xmiNS
		elemAttrs['uuid'].namespace = xmiNS
	end

	isReadOnly = false
	propReadOnly = prop["isReadOnly"]
	if propReadOnly != nil
		isReadOnly = (propReadOnly == "true")
	end

	if prop.name == "ownedAttribute" && !isReadOnly
		type = prop.at('type')
		if type == nil
			# Get the attributes from the Node Attributes
			elemAttrs = prop.attributes
			# use the type attribute
			type = inxml.xpath("//*[@xmi:id='" + elemAttrs["type"] + "']").first
		end

		if type == nil
			puts "No type declared for "+prop['name'].to_s
		else
			if type.attributes()['type'].to_s == "uml:Class"
				inAgg = prop["aggregation"]
				if inAgg == "composite"
					stereo = Nokogiri::XML::Node.new('PartProperty', inxml)
				else
					stereo = Nokogiri::XML::Node.new('ReferenceProperty', inxml)
				end
			else
				stereo = Nokogiri::XML::Node.new('ValueProperty', inxml)
			end
			inxml.root.add_child stereo
			stereo.namespace = mdStereos
			stereo['id'] = prop.attributes()['id'].to_s + "-AS"
			stereo['base_Property'] = prop.attributes()['id'].to_s
			elemAttrs = stereo.attributes
			elemAttrs['id'].namespace = xmiNS
			elemAttrs['base_Property'].namespace = nil
		end
	end
end

#add MD specific constraint parameter stereotypes
constraints = inxml.xpath('//sysml:ConstraintBlock')
for constraint in constraints
	constraint_base = constraint["base_Class"].to_s.strip
	con = inxml.xpath('//packagedElement[@xmi:id="' + constraint_base + '"]').first
	ports = con.xpath('ownedAttribute  [@xmi:type="uml:Port"]')
	for port in ports
		stereo = Nokogiri::XML::Node.new('ConstraintParameter', inxml)
		inxml.root.add_child stereo
		stereo.namespace = mdStereos
		stereo['id'] = port.attributes()['id'].to_s + "-AS"
		stereo['base_Port'] = port.attributes()['id']
		elemAttrs = stereo.attributes
		elemAttrs['id'].namespace = xmiNS
		elemAttrs['base_Port'].namespace = nil
	end
end

#change L2 stereotype names so accepted by MD
l2Stereos = inxml.xpath('//StandardProfileL2:*')
for l2Stereo in l2Stereos
	l2Stereo.name = l2Stereo.name.downcase
end

File.open(xmi_output_file,"w"){|file| inxml.write_xml_to file}
if !File.writable?(uuidfilename)
	File.chmod(0644,uuidfilename)
end
File.open(uuidfilename,"w"){|file| $uuidxml.write_xml_to file}

stime = Time.now
puts 'END ' + stime.to_s
