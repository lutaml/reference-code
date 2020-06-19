#!/usr/bin/env ruby
require 'nokogiri'
require 'uuid'
require 'zip/filesystem'
include Nokogiri
## Canonical XMI to MagicDraw XMI module (MagicDraw 1.8)
## Version 0.2
## 2017-02-13
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
sw = "MagicDraw module generator"
swv = "$Revision: 1.2 $"
swv = swv.split(' ')[1]
xmi_input_file = " "
for arg in ARGV
	argarray = arg.split('=')
	if argarray[0]=="xmi"
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
dir_hash = Hash.new

#setup namespaces
xmiNS = inxml.root.namespace_definitions.find{|ns| ns.prefix=="xmi"}
umlNS = inxml.root.namespace_definitions.find{|ns| ns.prefix=="uml"}

#find the what type of file we are dealing with
plcsNS = inxml.root.namespaces["xmlns:PLCS"]
if !plcsNS.nil?
	block = inxml.root.xpath('PLCS:Template').first
else
	block = nil
end

sharedPackage = nil

path = File.expand_path File.dirname(xmi_input_file)
Dir.chdir(path)

uuidfilename = "dvlp\\UUIDs.xml"
if !block.nil?
	block_base = block["base_Class"].to_s.strip
	template = inxml.xpath('//packagedElement[@xmi:id="' + block_base + '"]').first
	templateName = template["name"].to_s.strip
	context = template.parent.parent.parent
	contextName = context["name"].to_s.strip
	sharedPackage = template.parent
	sharedContext = contextName +'::Templates::'
	xmi_output_file = "dvlp\\" + contextName + templateName + ".mdzip"
else
	templates = inxml.xpath('//packagedElement[@name="Templates"]').first
	if !templates.nil?
		context = templates.parent
		contextName = context["name"].to_s.strip
		xmi_output_file = "dvlp\\index.mdzip"
	else
		input_parts = xmi_input_file.split("\\")
		input_filename = input_parts[input_parts.size - 1]
		sharedPackage = inxml.xpath('//sharedPackage').first
		if !sharedPackage.nil?
			sharedPackage = sharedPackage.parent.parent
		end
		sharedContext = ''
		if input_filename == "plcs_psm.xmi"
			xmi_output_file = "dvlp\\plcs_psm_module.mdzip"
		else
			filename = File.basename(input_filename,".xmi")
			if Dir.exists?("dvlp")
				filename = "dvlp\\" + filename
			end
			xmi_output_file = filename + ".mdzip"
			uuidfilename = filename + "_UUIDs.xml"
		end
	end
end

$uuid = UUID.new
$metaFile = 'com.nomagic.ci.metamodel.project'
$modelFile = 'com.nomagic.magicdraw.uml_model.model'
projectFile = ''
proxyFile = ''

def buildFile(xmi_output_file, modelId)
	untitled = File.dirname(__FILE__)+"/Untitled1.mdzip"
	oldProjectFile = ''
	projectFile = "PROJECT-" + $uuid.generate
	zif = Zip::File.open(untitled)
	meta = zif.read($metaFile)
	metaxml = Nokogiri::XML(meta,&:noblanks)
	oldProjectFile = metaxml.root["id"]
	model = zif.read($modelFile)
	modelxml = Nokogiri::XML(model,&:noblanks)
	oldModelId = modelxml.xpath('//uml:Model/@xmi:id').first.to_s
	zif.close
	zof = Zip::File.open(xmi_output_file, Zip::File::CREATE)
	oldProjh = oldProjectFile.gsub('-', '$h')
	projh = projectFile.gsub('-', '$h')
	proxyFile = 'proxy.local__' + oldProjh + '_resource_com$dnomagic$dmagicdraw$duml_umodel$dmodel$dsnapshot'
	zif = Zip::File.open(untitled)
	zif.each { |f|
		case f.name
			when oldProjectFile
				text = f.get_input_stream.read
				zof.file.open(projectFile, 'w'){|file| file.puts text}
			when $modelFile, proxyFile
			else
				inf = Nokogiri::XML(f.get_input_stream,&:noblanks)
				if !inf.root.nil?
					projectRefs = inf.xpath('//@*[contains(.,"' + oldProjectFile + '")]')
					for project in projectRefs
						project.value = project.to_s.gsub(oldProjectFile, projectFile)
					end
					modelRefs = inf.xpath('//@*[contains(.,"' + oldModelId + '")]')
					for modelRef in modelRefs
						modelRef.value = modelRef.to_s.gsub(oldModelId, modelId)
					end
					zof.file.open(f.name, 'w'){|file| inf.write_xml_to file}
				else
					text = f.get_input_stream.read
					text = text.gsub(oldProjectFile, projectFile)
					text = text.gsub(oldProjh, projh)
					zof.file.open(f.name, 'w'){|file| file.puts text}
				end
		end
	}
	zif.close
	zof.close
  return projectFile
end

modelId = inxml.xpath('//uml:Model/@xmi:id').first
if FileTest.exist?(xmi_output_file) != true
	puts "Generating : " + xmi_output_file
  projectFile = buildFile(xmi_output_file, modelId)
else
	puts "Updating : " + xmi_output_file
	FileUtils.cp xmi_output_file, xmi_output_file + '.bak'
	zif = Zip::File.open(xmi_output_file)
	zif.each { |f|
		if /PROJECT-/.match(f.name)
			projectFile = f.name
		end
	}
	zif.close
end
projh = projectFile.gsub('-', '$h')
proxyFile = 'proxy.local__' + projh + '_resource_com$dnomagic$dmagicdraw$duml_umodel$dmodel$dsnapshot'

for xml_node in inxml.xpath( '//*[@href]' )
	href = xml_node["href"].to_s
	hrefparts = href.split('#')
	path = hrefparts[0]
	newpath = href_hash[path]
	if newpath.nil?
		if path.size > 0
			prot_parts = path.split(':')
			if prot_parts.size == 1
				directory = File.dirname(path) + '\\dvlp'
				if Dir.exists?(directory)
					newpath = File.basename(path, '.*') + '.mdzip'
					href_hash[path] = newpath
					dir_hash[path] = directory + '\\' + newpath
				else
					path_parts = path.split('\\')
					case path_parts.size
						when 2
						 # profile from index
							if path_parts[1] == "PLCS-profile.xmi"
							 newpath = "PLCS-profile.mdzip"
							 href_hash[path] = newpath
							else
								puts "Unknown href: " + href
							end
						when 3
							# Template in same context
							newpath = contextName + path_parts[1] + ".mdzip"
							href_hash[path] = newpath
						when 4
						 # profile
							if path_parts[3] == "PLCS-profile.xmi"
							 newpath = "PLCS-profile.mdzip"
							 href_hash[path] = newpath
							else
								puts "Unknown href: " + href
							end
						when 5
							if path_parts[4] == "plcs_psm.xmi"
								# PLCS_PSM reference!
								newpath = "plcs_psm_module.mdzip"
								href_hash[path] = newpath
							else
								# Template in another context from index
								newpath = path_parts[1] + path_parts[3] + ".mdzip"
								href_hash[path] = newpath
							end
						when 7
							if path_parts[6] == "plcs_psm.xmi"
								# PLCS_PSM reference!
								newpath = "plcs_psm_module.mdzip"
								href_hash[path] = newpath
							else
								# Template in another context
								newpath = path_parts[3] + path_parts[5] + ".mdzip"
								href_hash[path] = newpath
							end
						else
							puts "Unknown path: " + path.to_s
					end
				end
			else
				# A URI
				newpath = path
			end
		else
			# just an id!
			newpath = ""
		end
	end
	xml_node["href"] = newpath + "#" + hrefparts[1]
	if !dir_hash[path].nil?
		extension = Nokogiri::XML::Node.new('Extension', inxml)
		extension.namespace = xmiNS
		extension['extender'] = 'MagicDraw UML 18.4'
		xml_node.add_child extension
		refExtension = Nokogiri::XML::Node.new('referenceExtension', inxml)
		otherfile = File.new(path, "r")
		otherxml = Nokogiri::XML(otherfile,&:noblanks)
		element = otherxml.xpath('//*[@xmi:id="' + hrefparts[1] + '"]').first
		if !element.nil?
			refPath = element['name'].to_s
			parent = element.parent
			while parent.parent != otherxml.root
				refPath = parent['name'].to_s + '::' + refPath
				parent = parent.parent
			end
			refExtension['referentPath']= refPath
			refType = element.xpath('./@xmi:type').first.to_s
			if !refType.nil?
				refTypeParts = refType.split(':')
				refExtension['referentType']= refTypeParts[refTypeParts.size - 1]
			end
		end
		extension.add_child refExtension
		refExtension.namespace = nil
	end
end

model = inxml.xpath('//uml:Model')[0]
#Add resources
doc = inxml.xpath('//xmi:Documentation')[0]
if doc.nil?
	doc = Nokogiri::XML::Node.new('Documentation', inxml)
	doc.namespace = xmiNS
	model.add_previous_sibling doc
end

mainextension = Nokogiri::XML::Node.new('Extension', inxml)
mainextension.namespace = xmiNS
mainextension['extender'] = 'MagicDraw UML 18.4'
model.add_previous_sibling mainextension

plugin = Nokogiri::XML::Node.new('plugin', inxml)
plugin['pluginName']= 'SysML'
plugin['pluginVersion']= '18.4'
mainextension.add_child plugin
plugin.namespace = nil
plugin = Nokogiri::XML::Node.new('plugin', inxml)
plugin['pluginName']= 'Cameo Requirements Modeler'
plugin['pluginVersion']= '18.4'
mainextension.add_child plugin
plugin.namespace = nil
req_resource = Nokogiri::XML::Node.new('req_resource', inxml)
req_resource['resourceID']='1480'
req_resource['resourceName']= 'Cameo Requirements Modeler'
req_resource['resourceValueName']= 'Cameo Requirements Modeler'
mainextension.add_child req_resource
req_resource.namespace = nil
req_resource = Nokogiri::XML::Node.new('req_resource', inxml)
req_resource['resourceID']='1440'
req_resource['resourceName']= 'SysML'
req_resource['resourceValueName']= 'SysML'
mainextension.add_child req_resource
req_resource.namespace = nil

#parse meta file
zof = Zip::File.open(xmi_output_file)
meta = zof.read($metaFile)
metaxml = Nokogiri::XML(meta,&:noblanks)
zof.close

# add share
if !sharedPackage.nil?
	share = metaxml.xpath('//ownedSections[@name="shared_model"]').first
	if share.nil?
		share = Nokogiri::XML::Node.new('ownedSections',metaxml)
		metaxml.xpath('(//ownedSections)[last()]').first.add_next_sibling share
		share.namespace = nil
		shareId = $uuid.generate
		share['xmi:id'] = shareId
		share['name'] = "shared_model"
		share['shared'] = "true"
		modelFeature = metaxml.xpath('//features[@name="UML Model"]/@xmi:id').first.to_s
		share['featuredBy'] = modelFeature
		sharePoints = Nokogiri::XML::Node.new('sharePoints',metaxml)
		sharePoints['xmi:id'] = $uuid.generate
		sharePoints['ID'] = $uuid.generate
		share.add_child sharePoints
		object = Nokogiri::XML::Node.new('object',metaxml)
		object['href'] = projectFile + '?resource=com.nomagic.magicdraw.uml_umodel.shared_umodel#' + sharedPackage.attributes["id"].to_s.strip
		sharePoints.add_child object
		options = Nokogiri::XML::Node.new('options',metaxml)
		options['xmi:id'] = $uuid.generate
		options['key'] = "preferredPath"
		options['value'] = sharedContext
		sharePoints.add_child options
		umFeature = metaxml.xpath('//features[@name="UML Model"]').first
		umFeature['sections'] = umFeature['sections'] + ' ' +shareId
	end
end

# add mounts for imported packages
features = metaxml.xpath('//features').first
dir_hash.each do |path, filename|
	filepath = 'file:/' + filename.gsub(' ','%20')
	projectUsages = metaxml.xpath('//projectUsages[@usedProjectURI="'+filepath+'"]').first
	if projectUsages.nil?
		otherProject = ''
		projectUsages = Nokogiri::XML::Node.new('projectUsages',metaxml)
		projectUsages['xmi:id']=$uuid.generate
		projectUsages['usedProjectURI']=filepath
		projectUsages['readonly']="true"
		projectUsages['loadedAutomatically']="true"
		features.add_previous_sibling projectUsages
		projectUsages.namespace = nil
	if File.exists?(filename)
			zif = Zip::File.open(filename)
			zif.each { |f|
				if /PROJECT-/.match(f.name)
					otherProject = f.name
				end
			}
			zif.close
		else
			puts 'created stub file '+filename
			otherProject = buildFile(filename, modelId)
			puts "add share to meta"
			exit
		end
		zif = Zip::File.open(filename)
		otherMeta = zif.read($metaFile)
		otherMetaxml = Nokogiri::XML(otherMeta,&:noblanks)
		zif.close
		theId = otherMetaxml.xpath('//project:Project/@xmi:id').first.to_s
		usedProject = Nokogiri::XML::Node.new('usedProject',metaxml)
		usedProject['href'] = otherProject + '?resource=com.nomagic.ci.metamodel.project#' + theId
		projectUsages.add_child usedProject
		pkg = inxml.xpath( '//packagedElement[starts-with(@href,"' + href_hash[path] + '")]').first
		mountPoints = Nokogiri::XML::Node.new('mountPoints',metaxml)
		mountPoints['xmi:id'] = $uuid.generate
		theShare = otherMetaxml.xpath('//project:Project/ownedSections/sharePoints').first
		mountPoints['sharePointID'] = theShare['ID']
		mountPoints['containmentFeatureID'] = "61"
		mountPoints['featureName'] = "UML Model"
		mountPoints['containmentIndex'] = "-1"
		mountPoints['containmentFeatureName'] = "packagedElement"
		mountedPoint = Nokogiri::XML::Node.new('mountedPoint',metaxml)
		href = pkg["href"].to_s.strip
		href_parts = href.split('#')
		sharedHref = href_parts[1]
		mountedPoint['href'] = otherProject + '?resource=com.nomagic.magicdraw.uml_umodel.shared_umodel#' + sharedHref
		mountPoints.add_child mountedPoint
		mountedOn = Nokogiri::XML::Node.new('mountedOn',metaxml)
		mountOnId = pkg.parent.attributes["id"].to_s.strip
		mountedOn['href'] = projectFile + '?resource=com.nomagic.magicdraw.uml_umodel.model#' + mountOnId
		mountPoints.add_child mountedOn
		options = Nokogiri::XML::Node.new('options',metaxml)
		options['xmi:id'] = $uuid.generate
		options['key'] = "preferredPath"
		preferredPath = theShare.xpath('./options[@key="preferredPath"]').first
		options['value'] = preferredPath['value']
		mountPoints.add_child options
		mountedSharePoint = Nokogiri::XML::Node.new('mountedSharePoint',metaxml)
		mountedSharePoint['href'] = otherProject + '?resource=com.nomagic.ci.metamodel.project#' + theShare.attributes()['id']
		mountPoints.add_child mountedSharePoint
		projectUsages.add_child mountPoints
		properties = Nokogiri::XML::Node.new('properties',metaxml)
		properties['xmi:id'] = $uuid.generate
		properties['key'] = "LOCAL_PROJECT_ID"
		properties['value'] = otherProject
		projectUsages.add_child properties
		properties = Nokogiri::XML::Node.new('properties',metaxml)
		properties['xmi:id'] = $uuid.generate
		properties['key'] = "loadIndex"
		properties['value'] = "true"
		projectUsages.add_child properties
	end
end

if File.exists?(uuidfilename)
	uuidfile = File.open(uuidfilename)
	$uuidxml = Nokogiri::XML(uuidfile, &:noblanks)
	uuidfile.close
else
	$uuidxml = Nokogiri::XML::Builder.new { |b| b.uuids }.doc
end

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
props = inxml.xpath('(//ownedAttribute | //ownedEnd)[@xmi:type="uml:Property" or @xmi:type="uml:Port"]')
#need to add the namespace (nokogiri complains otherwise)
mdStereos = inxml.root.add_namespace_definition('MD_Customization_for_SysML__additional_stereotypes','http://www.magicdraw.com/spec/Customization/180/SysML')
for prop in props
	if prop.at('lowerValue') == nil
		extension = Nokogiri::XML::Node.new('Extension', inxml)
		extension.namespace = xmiNS
		extension['extender'] = 'MagicDraw UML 18.4'
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
		extension['extender'] = 'MagicDraw UML 18.4'
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
			puts elemAttrs["type"].to_s
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

	redefined = prop['redefinedProperty']
	if !redefined.nil?
		redefinedElem = Nokogiri::XML::Node.new('redefinedProperty', inxml)
		redefinedElem['xmi:idref'] = redefined
		prop.prepend_child redefinedElem
		prop.attribute('redefinedProperty').remove
	end
end

#remove uuid from stereotypes
stereos = inxml.xpath('(//sysml:* | //StandardProfile:*)[@xmi:uuid]')
for stereo in stereos
	stereo.attribute_with_ns('uuid',xmiNS.href).remove
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

#sort out appiedProfile if defined
for appliedProfile in inxml.xpath('//appliedProfile')
	extension = Nokogiri::XML::Node.new('Extension', inxml)
	extension.namespace = xmiNS
	extension['extender'] = 'MagicDraw UML 18.4'
	refExt = Nokogiri::XML::Node.new('referenceExtension', inxml)
	href = appliedProfile["href"]
	case href
		when "http://www.omg.org/spec/SysML/20150709/SysML.xmi#_SysML__0", "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
			refPath = 'SysML'
			originalID = '_11_5EAPbeta_be00301_1147434586638_637562_1900'
		else
			hrefparts = href.split('#')
			if hrefparts[0] == "PLCS-profile.mdzip"
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
	refExt['originalID'] = originalID
	extension.add_child refExt
	refExt.namespace = nil
	proExtension = extension.dup

	profile = inxml.xpath( '//packagedElement[@href="' + href + '"]').first
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

if !sharedPackage.nil?
	spCopy = sharedPackage.dup
	spParentId = sharedPackage.parent.attributes["id"].to_s.strip
	spCopy.name = "Package"
	pe = Nokogiri::XML::Node.new('packagedElement', inxml)
	pe['href'] = 'local:/' + projectFile + '?resource=com.nomagic.magicdraw.uml_umodel.shared_umodel#' + sharedPackage.attributes["id"].to_s.strip
	sharedPackage.add_previous_sibling pe
	pe.namespace = nil
	extension = Nokogiri::XML::Node.new('Extension', inxml)
	extension.namespace = xmiNS
	extension['extender'] = 'MagicDraw UML 18.4'
	pe.add_child extension
	refExtension = Nokogiri::XML::Node.new('referenceExtension', inxml)
	refExtension['referentPath'] = sharedContext + sharedPackage.attributes["name"].to_s.strip
	refExtension['referentType'] = 'Package'
	extension.add_child refExtension
	refExtension.namespace = nil
	sharedPackage.remove
	zof = Zip::File.open(xmi_output_file)
	if !zof.file.exists?('com.nomagic.magicdraw.uml_model.shared_model')
		NS = {
			"xmlns:uml"							                                                         => 'http://www.omg.org/spec/UML/20131001',
			"xmlns:xmi"							                                                         => 'http://www.omg.org/spec/XMI/20131001',
			"xmlns:sysml"                                                                    => 'http://www.omg.org/spec/SysML/20150709/SysML',
			"xmlns:StandardProfile"                                                     => 'http://www.omg.org/spec/UML/20131001/StandardProfile',
			"xmlns:MagicDraw_Profile"                                                  => 'http://www.omg.org/spec/UML/20131001/MagicDrawProfile',
			"xmlns:MD_Customization_for_Requirements__additional_stereotypes" => 'http://www.magicdraw.com/spec/Customization/180/Requirements',
			"xmlns:DSL_Customization"                                                            => 'http://www.magicdraw.com/schemas/DSL_Customization.xmi',
			"xmlns:MD_Customization_for_SysML__additional_stereotypes"           => 'http://www.magicdraw.com/spec/Customization/180/SysML',
			"xmlns:Validation_Profile"                                                          => 'http://www.magicdraw.com/schemas/Validation_Profile.xmi'
		}
		sharedFile = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml|
			xml.XMI(NS) {
				xml.Documentation{
					xml.exporter "MagicDraw UML"
					xml.exporterVersion "18.4 v2"
				}
				xml.Extension(:extender => 'MagicDraw UML 18.4'){
					xml.plugin(:pluginName => 'SysML', :pluginVersion => '18.4')
					xml.plugin(:pluginName => 'Cameo Requirements Modeler', :pluginVersion => '18.4')
					xml.req_resource(:resourceID => '1480', :resourceName => 'Cameo Requirements Modeler', :resourceValueName => 'Cameo Requirements Modeler')
					xml.req_resource(:resourceID => '1440', :resourceName => 'SysML', :resourceValueName => 'SysML')
				}
			}
		}.doc
		xmiSF = sharedFile.root.namespace_definitions.find{|ns| ns.prefix=="xmi"}
		sharedFile.root.namespace = xmiSF
		doc = sharedFile.xpath('//Documentation').first
		doc.namespace=xmiSF
		for child in doc.children
			child.namespace = xmiSF
		end
		ext = sharedFile.xpath('//Extension').first
		ext.namespace = xmiSF

		sharePoints = Nokogiri::XML::Builder.new(:encoding => "ASCII") { |xml|
			xml.Package("xmi:version"  => "2.0",
													"xmlns:xmi" => "http://www.omg.org/XMI",
													"xmlns:uml" => "http://www.nomagic.com/magicdraw/UML/2.5",
													"xmi:id" => spCopy.attributes["id"],
													"ID" => spCopy.attributes["id"],
													"name" => spCopy["name"]){
				xml.owningPackage("href" => projectFile + "?resource=com.nomagic.magicdraw.uml_umodel.model#" + spParentId)
			}
		}.doc
		sharePoints.root.namespace = sharePoints.root.namespace_definitions.find{|ns| ns.prefix=="uml"}
		zof.file.open('com.nomagic.magicdraw.uml_model____sharepoints.shared_model', 'w'){|file| sharePoints.write_xml_to file}
		zof.file.open('proxy.local__' + projh +'_resource_com$dnomagic$dmagicdraw$duml_umodel$dshared_umodel$dsnapshot', 'w'){|file| sharePoints.write_xml_to file}

		descriptor = zof.read('com.nomagic.ci.proxy.snapshot.descriptor.descriptors')
		descriptorFile = Nokogiri::XML(descriptor,&:noblanks)
		modelDesc = descriptorFile.xpath('//snaphotDescriptors[@originalResourceURI="local:/'+projectFile+'?resource=com.nomagic.magicdraw.uml_umodel.model"]').first
		scont = Nokogiri::XML::Node.new('sharePointContainers', descriptorFile)
		scont['xmi:id'] = $uuid.generate
		scont['fragment'] = modelId
		modelDesc.add_child scont
		scont.namespace = nil
		csp = Nokogiri::XML::Node.new('containedSharePoints', descriptorFile)
		csp.content = 'local:/' + projectFile + '?resource=com.nomagic.magicdraw.uml_model.shared_model#' + sharedPackage.attributes["id"].to_s.strip
		scont.add_child csp
		csp.namespace = nil
		shareDesc = Nokogiri::XML::Node.new('snaphotDescriptors', descriptorFile)
		shareDesc['xmi:id'] = $uuid.generate
		shareDesc['originalResourceURI'] = 'local:/' + projectFile + '?resource=com.nomagic.magicdraw.uml_model.shared_model'
		spo = Nokogiri::XML::Node.new('sharePointObjects', descriptorFile)
		spo.content = sharedPackage.attributes["id"].to_s.strip
		shareDesc.add_child spo
		modelDesc.add_next_sibling shareDesc
		zof.file.open('com.nomagic.ci.proxy.snapshot.descriptor.descriptors', 'w'){|file| descriptorFile.write_xml_to file}

		RPtext = zof.file.read('Records.properties')
		zof.file.open('Records.properties','w'){|file|
			file.puts RPtext
			file.puts 'com.nomagic.magicdraw.uml_model.shared_model=com.nomagic.magicdraw.uml_model.shared_model'
			file.puts 'com.nomagic.magicdraw.uml_model____sharepoints.shared_model=com.nomagic.magicdraw.uml_model____sharepoints.shared_model'
			file.puts 'proxy.local__' + projh +'_resource_com$dnomagic$dmagicdraw$duml_umodel$dshared_umodel$dsnapshot=proxy.local__' + projh +'_resource_com$dnomagic$dmagicdraw$duml_umodel$dshared_umodel$dsnapshot'
		}
	else
		sf = zof.read('com.nomagic.magicdraw.uml_model.shared_model')
		sharedFile = Nokogiri::XML(sf,&:noblanks)
		children = sharedFile.root.children
		for child in children
			case child.name
				when "Documentation", "Extension"
				else
					child.remove
			end
		end
	end
	sharedFile.root.add_child spCopy
	xmiSF = sharedFile.root.namespace_definitions.find{|ns| ns.prefix=="xmi"}
	umlSF = sharedFile.root.namespace_definitions.find{|ns| ns.prefix=="uml"}
	spCopy.namespace = umlSF
	spElems = spCopy.xpath('.//*')
	for elem in spElems
		if elem.namespace == xmiSF
			elem.namespace = nil
		else
			case elem.name
				when "Extension"
				else
					elem.namespace = nil
			end
		end
	end
	stereos = inxml.root.children
	for stereo in stereos
		xmiid = nil
		case stereo.name
			when "Auxiliary","Block","Type"
				xmiid = stereo["base_Class"]
			when "ValueType"
				xmiid = stereo["base_DataType"]
			when "PartProperty", "ReferenceProperty", "ValueProperty"
				xmiid = stereo["base_Property"]
		end
		if !xmiid.nil?
			if inxml.xpath("//*[@xmi:id='" + xmiid + "']").first.nil?
				stereoCopy = stereo.dup
				stereo.remove
				sharedFile.root.add_child stereoCopy
			end
		end
	end
	zof.file.open('com.nomagic.magicdraw.uml_model.shared_model', 'w'){|file| sharedFile.write_xml_to file}
	zof.close
end

zof = Zip::File.open(xmi_output_file)
if !zof.file.exists?(proxyFile)
	proxy = Nokogiri::XML::Builder.new(:encoding => "ASCII") { |xml|
		xml.Model("xmi:version" => "2.0",
										"xmlns:xmi" => "http://www.omg.org/XMI",
										"xmlns:uml" => "http://www.nomagic.com/magicdraw/UML/2.5",
										"xmi:id" => modelId,
										"ID" => modelId,
										"name" => model["name"],
										"visibility" => "public")
	}.doc
	proxy.root.namespace = proxy.root.namespace_definitions.find{|ns| ns.prefix=="uml"}
	zof.file.open(proxyFile, 'w'){|file| proxy.write_xml_to file}
end
zof.file.open($metaFile, 'w'){|file| metaxml.write_xml_to file}
zof.file.open($modelFile, 'w'){|file| inxml.write_xml_to file}
zof.close
if File.exists?(uuidfilename) && !File.writable?(uuidfilename)
	File.chmod(0644,uuidfilename)
end
File.open(uuidfilename,"w"){|file| $uuidxml.write_xml_to file}

stime = Time.now
puts 'END ' + stime.to_s
