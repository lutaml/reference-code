#!/usr/bin/env ruby
path = File.expand_path File.dirname(__FILE__) 
require 'nokogiri'
require path + '/../Ruby/sysml'
require 'uuid'
require 'pathname'
include Nokogiri
include SYSML
## Eclipse UML Model framework to Canonical XMI
## Version 0.1
## 2015-02-19
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
sw = "Canonical XMI generator for Eclipse UML Model framework"
swv = "$Revision: 1.2 $"
swv = swv.split(' ')[1]
xmi_input_file = " "
for arg in ARGV
	argarray = arg.split('=')
	if argarray[0] == "xmi"
		xmi_input_file = argarray[1]
	end
	
	if argarray[0] == "help" or argarray[0] == "-help" or argarray[0] == "--help" or argarray[0] == "-h" or argarray[0] == "--h"
		puts "#{sw} Version #{swv}"
		puts " "
		puts "Usage parameters : xmi=<eclipse sysml.uml>"
		puts " "
		puts "  <eclipse sysml.uml> required input SysML eclipse file"				
		exit
	end
end

if xmi_input_file == " "
	puts "#{sw} Version #{swv}"
	puts " "
	puts "ERROR : No XMI input"
	puts "Usage parameters : xmi=<eclipse sysml.uml>"
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

$uuid = UUID.new
xmiInputPath = Pathname.new(xmi_input_file)
input_fileName = xmiInputPath.basename(xmiInputPath.extname).to_s
xmiInputPath = xmiInputPath.realpath.dirname
xmifile = File.new(xmi_input_file, "r")
inxml = Nokogiri::XML(xmifile,&:noblanks)

xmi_elements = inxml.xpath("//xmi:XMI")
if xmi_elements.size == 0
	profiles = inxml.xpath("//uml:Profile")
	case profiles.size
		when 0
			puts "#{sw} Version #{swv}"
			puts " "
			puts "ERROR : File contains no 'xmi:XMI' XML elements :  #{xmi_input_file}, may not be XMI file."
			xmifile.close
			exit
		when 1
			filetype = 'profile'
			output_fileName = input_fileName
			inTop = profiles[0]
		else
			puts "Only one profile definition per xmi file can be handled!"
			exit
	end		
end

inPLCSNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="PLCS"}
if inPLCSNS != nil
	filetype = 'plcslib'
	templates = inxml.xpath("//PLCS:Template")
	case templates.size
		when 0
			#find the local packages
			pkgs = inxml.xpath('//packagedElement[@xmi:type="uml:Package" and not(@href)]')
			tplpkgs = pkgs.select {|x| x["name"] == "Templates"}
			if tplpkgs.size == 0
				# A DEX?
				plcstype = 'dex'
				inTop = pkgs[0]
				output_fileName = inTop["name"]
			else
				plcstype = 'index'
				output_fileName = "index"
				contextName = xmiInputPath.basename.to_s
				inTop = inxml.xpath("//uml:Model").first
			end
		when 1
			plcstype = 'template'
			tmplId=templates[0]["base_Class"].to_s
			puts tmplId
			tmpl = inxml.xpath('//packagedElement[@xmi:id="'+tmplId+'"]').first
			output_fileName = tmpl["name"]
			inTop = tmpl.parent
		else
			puts "Found multiple templates"
			exit
	end
else
	#psm?
	if filetype != 'profile'
		output_fileName = input_fileName
		inTop = inxml.xpath("//uml:Model").first
	end
end

$basePath = xmiInputPath + ".."

Dir.chdir($basePath)

output_file = output_fileName + ".xmi"
puts "Generating : ..\\" + output_file

if File.exists?(output_file)
	oldfile = File.open(output_file)
	$oldxml = Nokogiri::XML(oldfile, &:noblanks)
	oldfile.close
end

uuidfilename = "dvlp\\UUIDs.xml"
if File.exists?(uuidfilename)	
	uuidfile = File.open(uuidfilename)
	$uuidxml = Nokogiri::XML(uuidfile, &:noblanks)
	uuidfile.close
else
	puts "uuid file not found"
	$uuidxml = Nokogiri::XML::Builder.new { |b| b.uuids }.doc
end	

def getOld(path, attrib)
	if $oldxml != nil
		element = $oldxml.xpath(path).first
		if element != nil
			return element.attributes()[attrib]
		end
	end
	if attrib == 'id'
		return '_'+$uuid.generate
	end
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

case filetype
	when 'profile'
		NS = {
			"xmi:version"            => "2.1",
			"xmlns:xmi"               => "http://schema.omg.org/spec/XMI/2.1",
			"xmlns:uml"               => "http://www.omg.org/spec/UML/20090901"
		}
		modelId = getOld('//xmi:XMI//uml:Model','id')
		$outputxml = Nokogiri::XML::Builder.new{ |xml| 
			xml.XMI(NS) {
				xml.Documentation("exporter" => sw, "exporterVersion" => swv)
				xml.Model(:name => "Data", "xmi:id" => modelId, "xmi:uuid" => get_uuid(modelId), "visibility" => "public"){
					xml.packagedElement("xmi:type" => "uml:Profile", "xmi:id" => inTop.attributes()["id"], "xmi:uuid" => get_uuid(inTop.attributes()["id"]), 
					                                 "name" => inTop["name"], "visibility" => "public")
					xml.packagedElement("xmi:type" => "uml:Profile", "href" => "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0")
				}
			}
		}.doc
		$outTop = $outputxml.xpath("//packagedElement").first
		outTopPath = "/xmi:XMI/uml:Model/packagedElement"
	when 'plcslib'
		NS = {
			"xmi:version"                   => "2.1",
			"xmlns:xmi"                      => "http://schema.omg.org/spec/XMI/2.1",
			"xmlns:sysml"                   => "http://www.omg.org/spec/SysML/20100301/SysML-profile",
			"xmlns:uml"                      => "http://www.omg.org/spec/UML/20090901",
			"xmlns:StandardProfileL2" => "http://schema.omg.org/spec/UML/2.3/StandardProfileL2.xmi",
			"xmlns:PLCS"                    => "http:///schemas/PLCS-profile.xmi"
		}
		if plcstype == 'index'
			modelId = getOld('//xmi:XMI//uml:Model','id')
			$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
				xml.XMI(NS) {
					xml.Documentation("exporter" => sw, "exporterVersion" => swv)
					xml.Model(:name => "Data", "xmi:id" => modelId, "xmi:uuid" => get_uuid(modelId), "visibility" => "public"){
						xml.packagedElement("xmi:type" => "uml:Profile", "href" => "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0")
					}
				}
			}.doc
			$outTop = $outputxml.xpath("//Model").first
			outTopPath = "/xmi:XMI/uml:Model"
		else
			## get upper structure from the index file
			indexfile = File.open('../../index.xmi')
			indexXml = Nokogiri::XML(indexfile, &:noblanks)
			indexfile.close
			model = indexXml.xpath('//xmi:XMI/uml:Model').first
			$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
				xml.XMI(NS) {
					xml.Documentation("exporter" => sw, "exporterVersion" => swv)
					xml.Model(:name => "Data", "xmi:id" => model.attributes()['id'], "xmi:uuid" => model.attributes()['uuid'], "visibility" => "public")
##					{
##						xml.packagedElement(:name => getOld('//xmi:XMI/uml:Model/packagedElement[0]','name'), "xmi:type" => "uml:Package", "xmi:id" => contextId, "xmi:uuid" => get_uuid(contextId), "visibility" => "public"){
##							xml.packagedElement("name" => inTop["name"], "xmi:type" => "uml:Package", "xmi:id" => inTop.attributes()['id']) 
##						}
##					}
				}
			}.doc
			target = indexXml.xpath('//packagedElement[@xmi:type="uml:Package" and contains(@href,"'+output_file+'")]').first
			package = Nokogiri::XML::Node.new("packagedElement", $outputxml)
			$outTop = package
			outTopPath = "/xmi:XMI/uml:Model/packagedElement"
			package['name'] = inTop['name']
			package['xmi:type'] = 'uml:Package'
			theId =  inTop.attributes()['id']
			package['xmi:id'] = theId
			package['xmi:uuid'] = get_uuid(theId)
			package['visibility'] = 'public'
			while target.parent.name != "Model"
				parent = Nokogiri::XML::Node.new("packagedElement", $outputxml)				
				parent['name'] = target.parent['name']
				parent['xmi:type'] = 'uml:Package'
				theId =  target.parent.attributes()['id']
				parent['xmi:id'] = theId
				parent['xmi:uuid'] = get_uuid(theId)
				parent['visibility'] = 'public'
				parent.add_child package
				outTopPath = outTopPath + '/packagedElement'
				package = parent
				target = target.parent
			end
			localTop = $outputxml.xpath("//Model").first
			localTop.add_child package
		end
	else
		NS = {
			"xmi:version"            => "20110701",
			"xmlns:xmi"               => "http://www.omg.org/spec/XMI/20110701",
			"xmlns:xsi"               => "http://www.w3.org/2001/XMLSchema-instance",
			"xmlns:ecore"            => "http://www.eclipse.org/emf/2002/Ecore",
			"xmlns:uml"               => "http://www.eclipse.org/uml2/4.0.0/UML",
			"xmlns:l2"                 => "http://www.eclipse.org/uml2/4.0.0/UML/Profile/L2"
			}
		sysmlObjs = inxml.xpath("//sysml:*")
		blocksNSneeded = false
		portsNSneeded = false
		constraintsNSneeded = false
		reqsNSneeded = false
		moElNSneeded = false
		for sysmlObj in sysmlObjs
			case sysmlObj.name
				when "Block", "ValueType", "NestedConnectorEnd", "BindingConnector"
					blocksNSneeded = true
				when "ConstraintBlock", "ConstraintProperty"
					constraintsNSneeded = true
				when "Rationale"
					moElNSneeded = true
				when "FlowPort"
					portsNSneeded = true
				when "Requirement"
					reqsNSneeded = true
			end
		end
		
		schemaLocation = ""
		
		if blocksNSneeded
			NS["xmlns:Blocks"] = "http://www.eclipse.org/papyrus/0.7.0/SysML/Blocks"
			schemaLocation = schemaLocation + " http://www.eclipse.org/papyrus/0.7.0/SysML/Blocks http://www.eclipse.org/papyrus/0.7.0/SysML#//blocks"
		end
		
		if constraintsNSneeded
			NS["xmlns:Constraints"] = "http://www.eclipse.org/papyrus/0.7.0/SysML/Constraints"
			schemaLocation = schemaLocation + " http://www.eclipse.org/papyrus/0.7.0/SysML/Constraints http://www.eclipse.org/papyrus/0.7.0/SysML#//constraints"
		end
		
		if moElNSneeded
			NS["xmlns:ModelElements"] = "http://www.eclipse.org/papyrus/0.7.0/SysML/ModelElements"
			schemaLocation = schemaLocation + " http://www.eclipse.org/papyrus/0.7.0/SysML/ModelElements http://www.eclipse.org/papyrus/0.7.0/SysML#//modelelements"
		end
		
		if portsNSneeded
			NS["xmlns:PortAndFlows"] = "http://www.eclipse.org/papyrus/0.7.0/SysML/PortAndFlows"
			schemaLocation = schemaLocation + " http://www.eclipse.org/papyrus/0.7.0/SysML/PortAndFlows http://www.eclipse.org/papyrus/0.7.0/SysML#//portandflows"
		end
		
		if reqsNSneeded
			NS["xmlns:Requirements"] = "http://www.eclipse.org/papyrus/0.7.0/SysML/Requirements"
			schemaLocation = schemaLocation + " http://www.eclipse.org/papyrus/0.7.0/SysML/Requirements http://www.eclipse.org/papyrus/0.7.0/SysML#//requirements"
		end
		
		NS["xsi:schemaLocation"] = schemaLocation
		paCount = 2

		$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
			xml.XMI(NS) {
				xml.Model(:name => "SysMLmodel") 
			}
		}.doc
		$outTop = $outputxml.xpath("//Model").first
		outTopPath = "/xmi:XMI/uml:Model"
end

$file_hash = Hash.new
$uuid_hash = Hash.new
$profiles = Hash.new

##inxml.root.add_namespace_definition("xmi","http://schema.omg.org/spec/XMI/2.1")

def getHref(href)
	hrefparts = href.split("#")
	filepath = hrefparts[0]
	id = hrefparts[1]
	if filepath.length == 0
		return id
	else
		newfilepath = $file_hash[filepath.to_s]
		if newfilepath == nil
			filepathparts = filepath.split(":")
			if filepathparts.size > 1
				filepathparts = filepathparts[1].split("/")
				indx = filepathparts.size - 1
				filename = filepathparts[indx]
				case filename
					when 'SysML.profile.uml', 'SysML'
						newfilepath = 'http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#'
					else
						puts 'Unknown standard href path: ' + filename
				end
			else
				filepathname = Pathname.new('dvlp/'+filepath)
				dir = filepathname.dirname.realpath + ".."
				base = filepathname.basename(".uml")
				filepathname = dir.relative_path_from($basePath) + base
				newfilepath = filepathname.to_s  + ".xmi#"
			end
			$file_hash[filepath.to_s] = newfilepath
		end	
		case newfilepath
			when 'http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#'
				case id
					when '_TZ_nULU5EduiKqCzJMWbGw'
					 id = '_0'
					when '_8J2A8LVAEdu2ieF4ON8UjA', '//blocks/Block'
					 id = 'Block'
					else
						puts 'Unknown id :' + id
				end
		end
		return newfilepath + id
	end
end	

def myCopy(obj, path, parent)
	newObj = Nokogiri::XML::Node.new(obj.name, $outputxml)
	## revert used profileApplications	
	case obj.name
		when 'profileApplication'
		puts obj
			for attr in obj.attribute_nodes
				if attr.name == "id"
						attr.name = "uuid"
				end
			end
			newPE = Nokogiri::XML::Node.new("packagedElement", $outputxml)
			newPE["type"] = "uml:Profile"
			newPE.attribute("type").namespace = $outxmiNS
			newPE['href'] = getHref(obj.at('appliedProfile')['href'])
			$outTop.add_child newPE
			## add SysML profile application here if not already here
			if newPE['href'] != 'http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0'
				newPA = Nokogiri::XML::Node.new("profileApplication", $outputxml)
				newPA["type"] = "uml:ProfileApplication"
				newPA.attribute("type").namespace = $outxmiNS
				newPA["uuid"] = getOld(path+"/profileApplication","uuid")
				newPA.attribute("uuid").namespace = $outxmiNS
				newAP = Nokogiri::XML::Node.new("appliedProfile", $outputxml)
				newAP['href'] = "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
				newAP['type'] = "uml:Profile"
				newAP.attribute("type").namespace = $outxmiNS
				newPA.add_child newAP
				parent.add_child newPA
			end
	end
		
	for attr in obj.attribute_nodes
		case attr.name
			when "href"
				newObj[attr.name] = getHref(attr.value)
			when "id"
				newObj[attr.name] = attr.value
				newObj["uuid"] = get_uuid(attr.value)
				newObj.attribute("uuid").namespace = $outxmiNS
			else
				newObj[attr.name] = attr.value
		end
		if newObj.attribute(attr.name) != nil
			if attr.namespace != nil
				if attr.namespace.prefix == "xmi"
					newObj.attribute(attr.name).namespace = $outxmiNS
				end
			end
		end
	end
	for child in obj.children
		if child.text?
			## ignore any text nodes that are just padding
			if (obj.content.tr("\n","").strip.length > 0)
				newObj.content = child.content
			end
		else
			newChild = myCopy(child, path+newObj.path, newObj)
			newObj.add_child newChild
		end
	end
	return newObj
end	

## remove classifier attribute from enumeration literals
enumLits = inTop.xpath(".//ownedLiteral [@xmi:type='uml:EnumerationLiteral']" )
for enumlit in enumLits
	if enumlit["classifier"] != nil
		enumlit.attributes["classifier"].remove
	end
end

## change case of requirement attributes
inReqsNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="Requirements"}
if inReqsNS != nil
	reqs = inTop.xpath("//Requirements:Requirement")
	for req in reqs
		req["Id"] = req["id"]
		req.attributes["id"].remove
		req["Text"] = req["text"]
		req.attributes["text"].remove
	end
end

## remove eclipse specific elements
eElems = inTop.xpath(".//eAnnotations" )
for eElem in eElems
	eElem.remove
end

## remove profileApplications from inTop
pas = inTop.xpath("./profileApplication")
for pa in pas
	pa.remove
end

$outxmiNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="xmi"}
outSysmlNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="sysml"}

## copy model over changing xmi namespace
children = inTop.xpath("./*")
firstchild = $outTop.children.first
for child in children
  childCopy = myCopy(child, outTopPath, $outTop)
	if firstchild != nil
		firstchild.add_previous_sibling childCopy
	else
		$outTop.add_child childCopy
	end
end

## copy any sysml nodes over changing sysml and xmi namespaces
inBlocksNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="Blocks"}
if inBlocksNS != nil
	sysmlObjs = inxml.xpath("//Blocks:*")
	for sysmlObj in sysmlObjs
		sysmlCopy = myCopy(sysmlObj, "/xmi:XMI", nil)
		$outputxml.root.add_child sysmlCopy
		sysmlCopy.namespace = outSysmlNS
	end
end

inConstraintsNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="Constraints"}
if inConstraintsNS != nil
	sysmlObjs = inxml.xpath("//Constraints:*")
	for sysmlObj in sysmlObjs
		sysmlCopy = myCopy(sysmlObj, "/xmi:XMI", nil)
		$outputxml.root.add_child sysmlCopy
		sysmlCopy.namespace = outSysmlNS
	end
end	

inMoElNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="ModelElements"}
if inMoElNS != nil
	sysmlObjs = inxml.xpath("//ModelElements:*")
	for sysmlObj in sysmlObjs
		sysmlCopy = myCopy(sysmlObj, "/xmi:XMI", nil)
		$outputxml.root.add_child sysmlCopy
		sysmlCopy.namespace = outSysmlNS
	end
end

inPortsNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="PortAndFlows"}
if inPortsNS != nil
	sysmlObjs = inxml.xpath("//PortAndFlows:*")
	for sysmlObj in sysmlObjs
		sysmlCopy = myCopy(sysmlObj, "/xmi:XMI", nil)
		$outputxml.root.add_child sysmlCopy
		sysmlCopy.namespace = outSysmlNS
	end
end

inReqsNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="Requirements"}
if inReqsNS != nil
	sysmlObjs = inxml.xpath("//Requirements:*")
	for sysmlObj in sysmlObjs
		sysmlCopy = myCopy(sysmlObj, "/xmi:XMI", nil)
		$outputxml.root.add_child sysmlCopy
		sysmlCopy.namespace = outSysmlNS
	end
end

outL2NS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="StandardProfileL2"}

## copy any L2 nodes over changing L2 and xmi namespaces
inStdNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="l2"}
if inStdNS != nil
	l2Objects = inxml.xpath("//l2:*")
	for l2Object in l2Objects
		newObj = myCopy(l2Object, "/xmi:XMI", nil)
		$outputxml.root.add_child newObj
		newObj.namespace = outL2NS
	end
end

## copy over any profile based nodes
$profiles.each_value {|value| 
  prefix = value["nsPrefix"]
	outprefNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix==prefix}
	prefObjects = inxml.xpath("//"+prefix+":*")
	for prefObject in prefObjects
		newObj = myCopy(prefObject, "/xmi:XMI", nil)
		$outputxml.root.add_child newObj
		newObj.namespace = outprefNS
	end
}

outModel = $outputxml.xpath("//Model").first
outModel.namespace = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="uml"}
outModel.parent.namespace = $outxmiNS

File.open(output_file,"w"){|file| $outputxml.write_xml_to file} 

stime = Time.now
puts 'END ' + stime.to_s
