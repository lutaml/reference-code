#!/usr/bin/env ruby
path = File.expand_path File.dirname(__FILE__) 
require 'nokogiri'
require path + '/../Ruby/sysml'
require 'uuid'
include Nokogiri
include SYSML
## UModel ump subproject to Canonical XMI
## Version 0.1
## 2015-02-23
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
xmi_input_file = " "
for arg in ARGV
	argarray = arg.split('=')
	if argarray[0] == "xmi"
		xmi_input_file = argarray[1]
	end
	
	if argarray[0] == "help" or argarray[0] == "-help" or argarray[0] == "--help" or argarray[0] == "-h" or argarray[0] == "--h"
		puts "to_cxmi Version 0.1"
		puts " "
		puts "Usage parameters : xmi=<UModel sysml.ump>"
		puts " "
		puts "  <UModel sysml.ump> required input UModel SysML file"				
		exit
	end
end

if xmi_input_file == " "
	puts "to_cxmi Version 0.1"
	puts " "
	puts "ERROR : No ump input"
	puts "Usage parameters : xmi=<UModel sysml.ump>"
	exit
end
if FileTest.exist?(xmi_input_file) != true
	puts "to_cxmi Version 0.1"
	puts " "
	puts "ERROR : UModel input file not found : #{xmi_input_file}"
	exit
end
##
##  Set up XMI File and template output file
##
stime = Time.now
puts 'START ' + stime.to_s

$uuid = UUID.new
xmifile = File.new(xmi_input_file, "r")
inxml = Nokogiri::XML(xmifile)

xmi_elements = inxml.xpath("//UModel")
if xmi_elements.size == 0
	puts "to_cxmi Version 0.1"
	puts " "
	puts "ERROR : File contains no 'UModel' XML elements :  #{xmi_input_file}, may not be UModeld file."
	xmifile.close
	exit
end

#find the local packages
pkgs = inxml.xpath('//Package[not(@href)]')
$outPackage = ""
tplpkgs = pkgs.select {|x| x["name"] == "Templates"}
if tplpkgs.size == 0
	topPackages = []
	# profile or psm
	for pkg in pkgs
		if !pkgs.include?(pkg.parent)
			topPackages.push pkg
		end
	end
	case topPackages.size
		when 0
			profiles = inxml.xpath('//Profile[not(@href)]')
			if profiles.size == 1
				if profiles[0]["name"] == "PLCS"
					$outPackage = "PLCS"
					output_file = "..\\PLCS-profile.xmi"
				end
			end
		when 1
			$outPackage = topPackages[0]["name"]
			output_file = "..\\plcs_psm.xmi"
		else
			puts "No idea which package to output!"
	end
else
	for tplpkg in tplpkgs
		innerPackages = tplpkg.xpath("./packagedElement/* [@name]") 
		# A template
		if innerPackages.size == 1
			if $outPackage == ""
				$outPackage = innerPackages[0]["name"]
				output_file = "..\\" + $outPackage + ".xmi"
			else
				puts "Found multiple output candidates " + $outPackage + " and " + innerPackages[0]["name"]
			end
		end
	end
  dxpkgs = pkgs.select {|x| x["name"] == "DEXs"}
	for dxpkg in dxpkgs
		innerPackages = dxpkg.xpath("./* [@name]") 
		# A DEX
		if innerPackages.size == 1
			if $outPackage == ""
				$outPackage = innerPackages[0]["name"]
				output_file = "..\\" + $outPackage + ".xmi"
			else
				puts "Found multiple output candidates " + $outPackage + " and " + innerPackages[0]["name"]
				exit
			end
		end
	end
	# a context index
	if tplpkgs.size > 0 && $outPackage == ""
		isIndex = true
		$outPackage = tplpkgs[0].parent["name"]
		output_file = "..\\" + $outPackage + ".xmi"
	end	
end

path = File.expand_path File.dirname(xmi_input_file) 
Dir.chdir(path)

puts "Generating : " + output_file

$file_hash = Hash.new
$uuid_hash = Hash.new
$lds = []

$xmiNS = inxml.root.namespace_definitions.find{|ns| ns.prefix=="xmi"}

if File.exists?(output_file)
	oldfile = File.open(output_file)
	$oldxml = Nokogiri::XML(oldfile, &:noblanks)
	oldfile.close
end

def getOldUUID(context, path)
	if $oldxml != nil
		element = $oldxml.xpath('//*[@uuid="' + context + '"]').first
		if element != nil
			target = element.xpath(path).first
			if target != nil
				return target.attributes()['uuid']
			end
		end
	end
	return $uuid.generate
end

def getHref(href)
	hrefparts = href.split("#")
	filepath = hrefparts[0]
	id = hrefparts[1]
	newfilepath = $file_hash[filepath]
	if newfilepath == nil
		filepathparts = filepath.split("\\")
		indx = filepathparts.size - 1
		filename = filepathparts[indx]
		filepathparts[indx] = "dvlp"
		path = filepathparts.join("\\")
		fileparts = filename.split(".")
		newfilepath = "..\\" + path + "\\" + fileparts[0] + ".ump#"
		$file_hash[filepath] = newfilepath
		uuidfilepath = path + "\\UUIDs.xml"
		if File.exists?(uuidfilepath)
			uuidfile = File.new(uuidfilepath, "r")
			uuidsxml = Nokogiri::XML(uuidfile)
			$uuid_hash[filepath] = uuidsxml
			uuidfile.close
		else
			puts "Missing file: " + uuidfilepath
		end
	end	
	uuidsxml = $uuid_hash[filepath]
	if uuidsxml != nil
		uuidmap = uuidsxml.xpath('//uuidmap[@id="' + id + '"]').first
		if uuidmap != nil
			return newfilepath + uuidmap["uuid"]
		else
			puts "UUID not found for id: " + id + " in file " + newfilepath
		end
	else
		return "unknown#1"
	end
end	

def getUUID(href)
	return getHref(href).split("#")[1]
end

def newElement(inxml, inElement, outputxml, outParent)
	outElem = nil
	if inElement == nil
		puts "oops!"
	end
	
	case inElement.attribute_with_ns('type',$xmiNS.href).to_s
		when "uml:Association"
			outElem = Nokogiri::XML::Node.new("Association", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			generals = inElement.xpath("generalization [@xmi:type='uml:Generalization']")
			if generals.size > 0
				general = Nokogiri::XML::Node.new("generalization", outputxml)
				outElem.add_child general
				generals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						general.add_child childElem
					end
				end
			end
			inOwnedEnd = inElement.at("ownedEnd")
			members = inElement.xpath("memberEnd")
			for member in members
				if (inOwnedEnd == nil) || (member.attributes["idref"].to_s != inOwnedEnd.attributes["id"].to_s)
					memberEnd = Nokogiri::XML::Node.new("memberEnd", outputxml)
					memberId = inxml.xpath("//*[@xmi:id='" + member.attributes["idref"].to_s + "']").first
					memberEnd["idref"] = memberId.attributes["uuid"].to_s
					outElem.add_child memberEnd
				end
			end
			if inOwnedEnd != nil
				ownedEnd = Nokogiri::XML::Node.new("ownedEnd", outputxml)
				outElem.add_child ownedEnd
				childElem = newElement(inxml, inOwnedEnd, outputxml, nil)
				ownedEnd.add_child childElem
			end

		when "uml:Class"
			outElem = Nokogiri::XML::Node.new("Class", outputxml)
			localContext =  inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			if inElement["isAbstract"] == "TRUE"
				outElem["isAbstract"] = "true"
			end
			constraints = inElement.xpath("ownedRule [@xmi:type='uml:Constraint']")
			if constraints.size > 0
				ownRule = Nokogiri::XML::Node.new("ownedRule", outputxml)
				outElem.add_child ownRule
				constraints.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						ownRule.add_child childElem
					end
				end
			end
			stereos = inxml.xpath("//*[@base_Class='" + inElement.attributes["id"].to_s + "']")
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				for  stereo in stereos
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "Auxiliary" then sa["classifier"] = "7102e796-9086-47f5-96b0-853473b344a9"
						when "Block" then sa["classifier"] = "e4e81567-6dce-4813-8431-e12861f73eaf"
						when "ConstraintBlock" then sa["classifier"] = "e72d0748-2b69-4b9f-9f5a-fd280926a1fb"
						when "Template" 
							# need to add block stereotype first for correct display in UModel
							sa["classifier"] = "e4e81567-6dce-4813-8431-e12861f73eaf"
							as.add_child sa
							sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
							sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication[2]")
							sa["classifier"] = "affdcd8a-6dcb-11e1-9cc6-47894775b647"
						when "Type" then sa["classifier"] = "623be4f7-5916-4a61-ba05-9360d99411f6"
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			generals = inElement.xpath("generalization [@xmi:type='uml:Generalization']")
			if generals.size > 0
				general = Nokogiri::XML::Node.new("generalization", outputxml)
				outElem.add_child general
				generals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						general.add_child childElem
					end
				end
			end
			connectors = inElement.xpath("ownedConnector")
			if connectors.size > 0
				owncon = Nokogiri::XML::Node.new("ownedConnector", outputxml)
				outElem.add_child owncon
				connectors.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						owncon.add_child childElem
					end
				end
			end
			attributes = inElement.xpath("ownedAttribute")
			if attributes.size > 0
				ownatt = Nokogiri::XML::Node.new("ownedAttribute", outputxml)
				outElem.add_child ownatt
				attributes.each do |child|
					childElem = newElement(inxml, child, outputxml, outElem)
					if childElem != nil
						ownatt.add_child childElem
					end
				end
			end
			
		when "uml:Connector"
			outElem = Nokogiri::XML::Node.new("Connector", outputxml)
			localContext = inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			stereos = inxml.xpath("//*[@base_Connector='" + inElement.attributes["id"].to_s + "']")
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				for  stereo in stereos
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "BindingConnector"
							sa["classifier"] = "031b6ba2-6c90-4e17-9695-2a132bef2b5c"
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			nd = Nokogiri::XML::Node.new("end", outputxml)
			outElem.add_child nd
			ends = inElement.xpath("end")
			for anEnd in ends
				conEnd = Nokogiri::XML::Node.new("ConnectorEnd", outputxml)
				localContext = anEnd.attributes["uuid"].to_s
				conEnd["uuid"] = localContext
				role = anEnd.at("role")
				if role == nil
					role = inxml.xpath("//*[@xmi:id='" + anEnd["role"] + "']").first
					roleUUID = role.attributes["uuid"].to_s
				else
					# Get the href attribute of the role element
					href = role["href"]
					roleUUID = getUUID(href)
				end
				stereos = inxml.xpath("//*[@base_ConnectorEnd='" + anEnd.attributes["id"].to_s + "']")
				if stereos.size > 0 
					as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
					conEnd.add_child as
					for  stereo in stereos
						sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
						if stereo.attributes["uuid"] == nil
							sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
						else
							sa["uuid"] = stereo.attributes["uuid"].to_s
						end
						# set classifier default to "none" to be checked before adding to the structure.
						sa["classifier"] = "none"
						case stereo.name
							when "NestedConnectorEnd" 
								sa["classifier"] = "fb157b3b-8b64-4398-871f-2cdea7a0467b"
								slot = Nokogiri::XML::Node.new("slot", outputxml)
								sa.add_child slot
								theSlot = Nokogiri::XML::Node.new("Slot", outputxml)
								theSlot["uuid"] = getOldUUID(sa["uuid"],"slot/Slot")
								theSlot["definingFeature"] = "f1ed6c88-38cb-4dfc-8dce-0f68e879bad2"
								slot.add_child theSlot
								value = Nokogiri::XML::Node.new("value", outputxml)
								theSlot.add_child value
								propPaths = stereo.xpath("propertyPath")
								if propPaths.size > 0
									localIndex = 0
									for inPP in propPaths
										localIndex = localIndex + 1
										#use string until UModel correctly handles this area
										str = Nokogiri::XML::Node.new("LiteralString", outputxml)
										str["uuid"] = getOldUUID(theSlot["uuid"],"value/LiteralString["+localIndex.to_s+"]")
										str["visibility"] = "public"	
										href = inPP["href"]
										hrefparts = href.split("#")
										filepath = hrefparts[0]
										id = hrefparts[1]
										if filepath.length == 0
											propPath = inxml.xpath("//*[@xmi:id='" + id + "']").first
										else
											otherfile = File.new(filepath, "r")
											otherxml = Nokogiri::XML(otherfile)
											otherfile.close
											propPath = otherxml.xpath("//*[@xmi:id='" + id + "']").first
										end
										if propPath != nil
											str["value"] = propPath["name"]
										else
											puts "Unresolved PropertyPath " + inPP
										end
										value.add_child str
									end
								else
									#use string until UModel correctly handles this area
									str = Nokogiri::XML::Node.new("LiteralString", outputxml)
									str["uuid"] = getOldUUID(theSlot["uuid"],"value/LiteralString")
									str["visibility"] = "public"	
									propPath = inxml.xpath("//*[@xmi:id='" + stereo["propertyPath"] + "']").first
									if propPath != nil
										str["value"] = propPath["name"]
									end
									value.add_child str
								end
							else puts "Unknown stereotype " + stereo.name
						end
						unless sa["classifer"] == "none"
							as.add_child sa
						end
					end
				end
				conEnd["role"] = roleUUID
				nd.add_child conEnd
			end

		when "uml:Constraint"
			outElem = Nokogiri::XML::Node.new("Constraint", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			if inElement["name"] == nil
				puts "Un-named constraint in " + inElement.parent["name"]
			else
				outElem["name"] = inElement["name"]
			end
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			constElem = Nokogiri::XML::Node.new("constrainedElement", outputxml)
			constElem["idref"] = inElement.parent.attributes["uuid"].to_s
			outElem.add_child constElem
			spec = Nokogiri::XML::Node.new("specification", outputxml)
			outElem.add_child spec
			expression = Nokogiri::XML::Node.new("OpaqueExpression", outputxml)
			inSpec = inElement.at("specification")
			expression["uuid"] = inSpec.attributes["uuid"].to_s
			expression["visibility"] = "public"
			expression["body"] = inSpec.at("body").content
			expression["language"] = inSpec.at("language").content
			spec.add_child expression
			
		when "uml:Enumeration"
			outElem = Nokogiri::XML::Node.new("Enumeration", outputxml)
			localContext = inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			if inElement["isAbstract"] == "TRUE"
				outElem["isAbstract"] = "true"
			end
			stereos = inxml.xpath("//*[@base_DataType='" + inElement.attributes["id"].to_s + "']")
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				for  stereo in stereos
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "ValueType" then sa["classifier"] = "669c0b26-32d4-49c9-b809-b207ba6b3906"
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			generals = inElement.xpath("generalization [@xmi:type='uml:Generalization']")
			if generals.size > 0
				general = Nokogiri::XML::Node.new("generalization", outputxml)
				outElem.add_child general
				generals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						general.add_child childElem
					end
				end
			end
			literals = inElement.xpath("ownedLiteral [@xmi:type='uml:EnumerationLiteral']")
			if literals.size > 0
				ownlit = Nokogiri::XML::Node.new("ownedLiteral", outputxml)
				outElem.add_child ownlit
				literals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						ownlit.add_child childElem
					end
				end
			end
			attributes = inElement.xpath("ownedAttribute")
			if attributes.size > 0
				ownatt = Nokogiri::XML::Node.new("ownedAttribute", outputxml)
				outElem.add_child ownatt
				attributes.each do |child|
					childElem = newElement(inxml, child, outputxml, outElem)
					if childElem != nil
						ownatt.add_child childElem
					end
				end
			end
		
		when "uml:EnumerationLiteral"
			outElem = Nokogiri::XML::Node.new("EnumerationLiteral", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			if inElement["isAbstract"] == "TRUE"
				outElem["isAbstract"] = "true"
			end
			outElem["classifier"] = inElement.parent.attributes["uuid"].to_s
			attributes = inElement.xpath("slot [@xmi:type='uml:Slot']")
			if attributes.size > 0
				slot = Nokogiri::XML::Node.new("slot", outputxml)
				outElem.add_child slot
				attributes.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						slot.add_child childElem
					end
				end
			end
		
		when "uml:Generalization"
			outElem = Nokogiri::XML::Node.new("Generalization", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			if inElement["general"] != nil
				general = inxml.xpath("//*[@xmi:id='" + inElement["general"] + "']").first
				outElem["general"] = general.attributes["uuid"]	.to_s
			else
				href = inElement.at("general")["href"]
				case href
					when "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#Block"
						outElem["general"] = "e4e81567-6dce-4813-8431-e12861f73eaf"
				end
			end

		when "uml:InstanceSpecification"
			outElem = Nokogiri::XML::Node.new("InstanceSpecification", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			# Need to do some serious work here to find the UUID for the classifier
			# it could be defined in the current file - in which case the classifier attribute gives us that
			# it could be defined in another file - in which case the classifier element would give us that via the href attribute defined inside the element
			if inElement.at('classifier') == nil
				# use the classifier attribute
				classifier = inxml.xpath("//*[@xmi:id='" + inElement["classifier"] + "']").first
				classifierUUID = classifier.attributes["uuid"].to_s
			else
				# Get the href attribute of the classifier element
				classifier = inElement.at('classifier')
				href = classifier["href"]
				isLink = (classifier.attributes["type"].to_s == 'uml:Association')
				classifierUUID = getUUID(href)
			end
			outElem["classifier"] = classifierUUID
			if isLink
				index = $lds.index {|ld| ld.association == classifierUUID}
				ld = $lds.delete_at (index)
				outElem["instanceSpecification_LinkBegin"] = ld.owner
				outElem["instanceSpecification_LinkEnd"] = ld.value 
			else
				attributes = inElement.xpath("slot [@xmi:type='uml:Slot']")
				if attributes.size > 0
					slot = Nokogiri::XML::Node.new("slot", outputxml)
					outElem.add_child slot
					attributes.each do |child|
						childElem = newElement(inxml, child, outputxml, nil)
						if childElem != nil
							slot.add_child childElem
						end
					end
				end
			end
		
		when "uml:Package"
			outElem = Nokogiri::XML::Node.new("Package", outputxml)
			href = inElement["href"]
			if href == nil
				localContext = inElement.attributes["uuid"].to_s
				outElem["uuid"] = localContext
				outElem["name"] = inElement["name"]
				if inElement["visibility"] == nil
					outElem["visibility"] = "public"
				else
					outElem["visibility"] = inElement["visibility"]
				end
				if inElement["name"] == $outPackage
					outElem["shared"] = "true"
				end
				pe = Nokogiri::XML::Node.new("packagedElement", outputxml)
				outElem.add_child pe
				# recurse to create the children in the packagedElement
				children = inElement.xpath("./*")
				localIndex = 0
				for child in children
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						if childElem.name == "ProfileApplication"
							localIndex = localIndex + 1
							# ProfileApplications do not go in a packagedElement but a single! profileApplication
							pa = outElem.xpath("./profileApplication").first
							if pa == nil
								pa = Nokogiri::XML::Node.new("profileApplication", outputxml)
								outElem.add_child pa
							end
							pa.add_child childElem
							# If this is the UModel SysML Profile, then force in the UML Profile too.
							if childElem["appliedProfile"] == "411fec0d-7aac-4cb3-9dae-f7d7cd254301"
								umlprofile = Nokogiri::XML::Node.new("ProfileApplication", outputxml)
								# Get the old UUID or generate a new UUID for this since not supplied in input XMI
								localIndex = localIndex + 1
								umlprofile["uuid"] = getOldUUID(localContext,"profileApplication/ProfileApplication["+localIndex.to_s+"]")
								umlprofile["appliedProfile"] = "00000101-7510-11d9-86f2-000476a22f44"
								pa.add_child umlprofile
							end
						else
							pe.add_child childElem
						end
					end
				end
			else
				outElem["href"] = getHref(href)
				outElem["editable"] = "false"
			end
			
		when "uml:Port"
			outElem = Nokogiri::XML::Node.new("Port", outputxml)
			localContext = inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			inAgg = inElement["aggregation"]
			if inAgg != nil
				outElem["aggregation"] = inAgg
			end
			inReadOnly = inElement["isReadOnly"]
			if inReadOnly != nil
				outElem["isReadOnly"] = inReadOnly
			end
			# Need to do some serious work here to find the UUID for the type
			# it could be defined in the current file - in which case the type attribute gives us that
			# 	(the type attribute can be difficult to get since there are the type and xmi:type attributes)
			# it could be defined in another file - in which case the type element would give us that via the href attribute defined inside the element
			type = inElement.at("type")
			if type == nil
				# Get the attributes from the Node Attributes
				typeId = inElement.attributes['type'].to_s
				if typeId != 'uml:Port'
					# use the type attribute
					type = inxml.xpath("//*[@xmi:id='" + typeId + "']").first
					typeUUID = type.attributes["uuid"].to_s
				else
					puts "Error: No type information for port " + inElement["name"]
				end
			else
				# Get the href attribute of the type element
				href = type["href"]
				typeUUID = getUUID(href)
			end
			outElem["type"] = typeUUID
			stereos = inxml.xpath("//*[@base_Port='" + inElement.attributes["id"].to_s + "']")
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				for  stereo in stereos
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "FlowPort" 
							sa["classifier"] = "e05699f3-1a66-4159-9f7f-1af2b2651f54"
							slot = Nokogiri::XML::Node.new("slot", outputxml)
							sa.add_child slot
							theSlot = Nokogiri::XML::Node.new("Slot", outputxml)
							theSlot["uuid"] = getOldUUID(sa["uuid"],"slot/Slot")
							theSlot["definingFeature"] = "477b6ae3-6b7e-4741-b80a-e9cdf4e1f667"
							slot.add_child theSlot
							value = Nokogiri::XML::Node.new("value", outputxml)
							theSlot.add_child value
							instanceValue = Nokogiri::XML::Node.new("InstanceValue", outputxml)
							instanceValue["uuid"] = getOldUUID(theSlot["uuid"],"value/InstanceValue")
							instanceValue["visibility"] = "public"
							case stereo["direction"]
								when "in" then instanceValue["instance"] = "de6801a5-eaf5-4e05-a8f2-a65832c81387"
								when "out" then instanceValue["instance"] = "7bd2eda1-2a62-43e3-b946-eed8c78dea0a"
								when "inout" then instanceValue["instance"] = "bc4976fc-15c1-407c-8eb1-2d2612f80e02"
							end
							value.add_child instanceValue
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			#LowerValue
			lval = Nokogiri::XML::Node.new("lowerValue", outputxml)
			outElem.add_child lval
			strLit = Nokogiri::XML::Node.new("LiteralString", outputxml)
			inLv = inElement.at("lowerValue")			
			if inLv == nil
				strLit["uuid"] = getOldUUID(localContext,"lowerValue/LiteralString")
			else
				strLit["uuid"] = inLv.attributes["uuid"].to_s
			end
			strLit["visibility"] = "public"
			if inLv == nil
				strLit["value"] = "1"
			else
				if inLv["value"] == nil
					strLit["value"] = "0"
				else
					strLit["value"] = inLv["value"]
				end
			end
			lval.add_child strLit
			#UpperValue
			uval = Nokogiri::XML::Node.new("upperValue", outputxml)
			outElem.add_child uval
			inUv = inElement.at("upperValue")			
			strLit = Nokogiri::XML::Node.new("LiteralString", outputxml)
			if inUv == nil
				strLit["uuid"] = getOldUUID(localContext,"upperValue/LiteralString")
			else
				strLit["uuid"] = inUv.attributes["uuid"].to_s
			end
			strLit["visibility"] = "public"
			if inUv == nil
				strLit["value"] = "1"
			else
				if inUv["value"] != nil
					strLit["value"] = inUv["value"]
				end
			end
			uval.add_child strLit
			
		when "uml:PrimitiveType"
			outElem = Nokogiri::XML::Node.new("PrimitiveType", outputxml)
			localContext = inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			if inElement["isAbstract"] == "TRUE"
				outElem["isAbstract"] = "true"
			end
			stereos = inxml.xpath("//*[@base_DataType='" + inElement.attributes["id"].to_s + "']")
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				localIndex = 0
				for  stereo in stereos
					localIndex = localIndex + 1
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype["+localIndex.to_s+"]/StereotypeApplication")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "ValueType" then sa["classifier"] = "669c0b26-32d4-49c9-b809-b207ba6b3906"
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			generals = inElement.xpath("generalization [@xmi:type='uml:Generalization']")
			if generals.size > 0
				general = Nokogiri::XML::Node.new("generalization", outputxml)
				outElem.add_child general
				generals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						general.add_child childElem
					end
				end
			end

		when "uml:Profile"
			href = inElement["href"]
			if href == nil
				# the profile is defined in this file!
				outElem = Nokogiri::XML::Node.new("Profile", outputxml)
				outElem["uuid"] = inElement.attributes["uuid"].to_s
				outElem["name"] = inElement["name"]
				if inElement["visibility"] == nil
					outElem["visibility"] = "public"
				else
					outElem["visibility"] = inElement["visibility"]
				end
				if inElement["name"] == $outPackage
					outElem["shared"] = "true"
				end
				pe = Nokogiri::XML::Node.new("packagedElement", outputxml)
				outElem.add_child pe
				# recurse to create the children in the packagedElement
				children = inElement.xpath("./*")
				for child in children
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						pe.add_child childElem
					end
				end
			else
				# Profiles can be defined in a number of places - need to sort out container
				if inElement.name == "appliedProfile"
					outElem = Nokogiri::XML::Node.new("ProfileApplication", outputxml)
					# The required UUID is on the parent in the input XMI
					outElem["uuid"] = inElement.parent.attributes["uuid"].to_s
					if href != "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
						outElem["appliedProfile"] = getUUID(href)
					else
						# we know the UUID for the SysML profile!
						outElem["appliedProfile"] = "411fec0d-7aac-4cb3-9dae-f7d7cd254301"
					end
				else
					#ignore the sysml profile - it is manually added later
					if href != "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
						outElem = Nokogiri::XML::Node.new("Profile", outputxml)
						outElem["href"] = getHref(href)
						outElem["editable"] = "false"
					end
				end
			end

		when "uml:ProfileApplication"
			children = inElement.xpath("./appliedProfile")
			# assume we only have one child for a ProfileApplication
			if children.size == 1
				outElem = newElement(inxml, children.first, outputxml, nil)
			else
				puts "Unexpected " + children.size.to_s + " children in: " + inElement.attributes["uuid"].to_s
			end
			
		when "uml:Property"
			outElem = Nokogiri::XML::Node.new("Property", outputxml)
			localContext = inElement.attributes["uuid"].to_s
			outElem["uuid"] = localContext
			if inElement["name"] != nil
				outElem["name"] = inElement["name"]
			end
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			inAgg = inElement["aggregation"]
			if inAgg != nil
				outElem["aggregation"] = inAgg
			end
			inReadOnly = inElement["isReadOnly"]
			if inReadOnly != nil
				outElem["isReadOnly"] = inReadOnly
			end
			# Need to do some serious work here to find the UUID for the type
			# it could be defined in the current file - in which case the type attribute gives us that
			# 	(the type attribute can be difficult to get since there are the type and xmi:type attributes)
			# it could be defined in another file - in which case the type element would give us that via the href attribute defined inside the element
			if inElement.at('type') == nil
				# Get the type attribute not to be confused with the xmi:type attribute
				type = inxml.xpath("//*[@xmi:id='" + inElement.attributes['type'].to_s + "']").first
				if type != nil
					typeUUID = type.attributes["uuid"].to_s
				else
					puts "Type missing for property: " + outElem["name"]
				end
			else
				# Get the href attribute of the type element
				type = inElement.at('type')
				href = type["href"]
				typeUUID = getUUID(href)
			end
			outElem["type"] = typeUUID
			inRedefinedProperty = inElement["redefinedProperty"]
			if inRedefinedProperty != nil
				ownRule = outParent.at('ownedRule') 
				if ownRule == nil
					ownRule = Nokogiri::XML::Node.new("ownedRule", outputxml)
					outParent.add_child ownRule
					localIndex = 1
				else
					localIndex = ownRule.xpath("Constraint").size + 1
				end
				const = Nokogiri::XML::Node.new("Constraint", outputxml)
				const["uuid"] = getOldUUID(outParent['uuid'],"ownedRule/Constraint["+localIndex.to_s+"]")
				const["visibility"] = "public"
				conElem = Nokogiri::XML::Node.new("constrainedElement", outputxml)
				redefined = inxml.xpath("//*[@xmi:id='" + inRedefinedProperty + "']").first
				if redefined != nil
					conElem["idref"] = outElem["uuid"]
					redef = redefined["name"]
					const.add_child conElem
				else
					puts "Missing redefinition for property: " + outElem["name"]
				end
				spec = Nokogiri::XML::Node.new("specification", outputxml)
				str = Nokogiri::XML::Node.new("LiteralString", outputxml)
				str["uuid"] = getOldUUID(const["uuid"],"specification/LiteralString")
				str["visibility"] = "public"				
				str["value"] = "redefines " + redef.to_s
				spec.add_child str
				const.add_child spec
				ownRule.add_child const
			end
			#Apply any sterotypes found in XMI file
			stereos = inxml.xpath("//*[@base_Property='" + inElement.attributes["id"].to_s + "']")
			as = nil
			if stereos.size > 0 
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				localIndex = 0
				for  stereo in stereos
					localIndex = localIndex + 1
					sa = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
					if stereo.attributes["uuid"] == nil
						sa["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication["+localIndex.to_s+"]")
					else
						sa["uuid"] = stereo.attributes["uuid"].to_s
					end
					# set classifier default to "none" to be checked before adding to the structure.
					sa["classifier"] = "none"
					case stereo.name
						when "ConstraintProperty" then sa["classifier"] = "d9eda5dc-cdd3-4240-8833-b09e630fdaf2"
						else puts "Unknown stereotype " + stereo.name
					end
					unless sa["classifer"] == "none"
						as.add_child sa
					end
				end
			end
			#UModel ShowAs stereotyping to part, reference, value
			# only applicable to properties within classes that are not constraintProperties
			if (as == nil) && (inElement.parent.attribute_with_ns('type',$xmiNS.href).to_s == "uml:Class")
				as = Nokogiri::XML::Node.new("appliedStereotype", outputxml)
				outElem.add_child as
				stereo = Nokogiri::XML::Node.new("StereotypeApplication", outputxml)
				as.add_child stereo
				stereo["uuid"] = getOldUUID(localContext,"appliedStereotype/StereotypeApplication")
				if type.attributes["type"].to_s == "uml:Class"
					if inAgg == "composite"
						stereo["classifier"] = "c0325157-f147-4dcc-8eee-894e3548da29"
					else
						stereo["classifier"] = "b1d2a8d8-7b01-4b42-8569-1e0584532d5e"
					end
				else
					stereo["classifier"] = "8ab949cf-a422-4100-8bbc-403b7a3f2914"
				end
			end
			#LowerValue
			lval = Nokogiri::XML::Node.new("lowerValue", outputxml)
			outElem.add_child lval
			strLit = Nokogiri::XML::Node.new("LiteralString", outputxml)
			inLv = inElement.at("lowerValue")			
			if inLv == nil
				strLit["uuid"] = getOldUUID(localContext,"lowerValue/LiteralString")
			else
				strLit["uuid"] = inLv.attributes["uuid"].to_s
			end
			strLit["visibility"] = "public"
			if inLv == nil
				strLit["value"] = "1"
			else
				if inLv["value"] == nil
					strLit["value"] = "0"
				else
					strLit["value"] = inLv["value"]
				end
			end
			lval.add_child strLit
			#UpperValue
			uval = Nokogiri::XML::Node.new("upperValue", outputxml)
			outElem.add_child uval
			inUv = inElement.at("upperValue")			
			strLit = Nokogiri::XML::Node.new("LiteralString", outputxml)
			if inUv == nil
				strLit["uuid"] = getOldUUID(localContext,"upperValue/LiteralString")
			else
				strLit["uuid"] = inUv.attributes["uuid"].to_s
			end
			strLit["visibility"] = "public"
			if inUv == nil
				strLit["value"] = "1"
			else
				if inUv["value"] != nil
					strLit["value"] = inUv["value"]
				end
			end
			uval.add_child strLit
			inDefault = inElement.at('defaultValue')
			if inDefault != nil
				default = Nokogiri::XML::Node.new("defaultValue", outputxml)
				outElem.add_child default
				litType = inDefault.attribute_with_ns('type',$xmiNS.href).to_s.split(":")[1]
				lit = Nokogiri::XML::Node.new(litType, outputxml)
				lit["uuid"] = inDefault.attributes["uuid"].to_s
				lit["visibility"] = inDefault["visibility"]
				case litType
					when "InstanceValue"
						instance = inDefault.at("instance")
						if instance == nil
							instance = inxml.xpath("//*[@xmi:id='" + inDefault["instance"] + "']").first
							instanceUUID = instance.attributes["uuid"].to_s
						else
							# Get the href attribute of the instance element
							href = instance["href"]
							instanceUUID = getUUID(href)
						end
						lit["instance"] = instanceUUID
					when "LiteralBoolean"
						if inDefault["value"] != nil
							lit["value"] = inDefault["value"]
						else
							lit["value"] = "false"
						end
					else
						lit["value"] = inDefault["value"]
				end
				default.add_child lit				
			end
			
		when "uml:Slot"
			outElem = Nokogiri::XML::Node.new("Slot", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			defFeature = inElement.at('definingFeature')
			if defFeature == nil
				defFeature = inxml.xpath("//*[@xmi:id='" + inElement["definingFeature"] + "']").first
				defFeatureUUID = defFeature.attributes["uuid"].to_s
			else
				href = defFeature["href"]
				defFeatureUUID = getUUID(href)
			end
			outElem["definingFeature"] = defFeatureUUID
			inValue = inElement.at('value')
			if inValue != nil
				value = Nokogiri::XML::Node.new("value", outputxml)
				outElem.add_child value
				litType = inValue.attribute_with_ns('type',$xmiNS.href).to_s.split(":")[1]
				lit = Nokogiri::XML::Node.new(litType, outputxml)
				lit["uuid"] = inValue.attributes["uuid"].to_s
				lit["visibility"] = inValue["visibility"]
				case litType
					when "InstanceValue"
						instance = inElement.at("instance")
						if instance == nil
							instance = inxml.xpath("//*[@xmi:id='" + inValue["instance"] + "']").first
							instanceUUID = instance.attributes["uuid"].to_s
						else
							# Get the href attribute of the instance element
							href = instance["href"]
							instanceUUID = getUUID(href)
						end
						lit["instance"] = instanceUUID
					else
						lit["value"] = inValue["value"]
				end
				value.add_child lit
			end
			
		when "uml:Stereotype"
			outElem = Nokogiri::XML::Node.new("Stereotype", outputxml)
			outElem["uuid"] = inElement.attributes["uuid"].to_s
			outElem["name"] = inElement["name"]
			if inElement["visibility"] == nil
				outElem["visibility"] = "public"
			else
				outElem["visibility"] = inElement["visibility"]
			end
			attributes = inElement.xpath("ownedAttribute")
			if attributes.size > 0
				attributes.each do |child|
					type = child.at("type")
					href = type["href"]
					typename = href.split("#")[1]
					outElem[child["name"]] = typename
				end
			end
			generals = inElement.xpath("generalization [@xmi:type='uml:Generalization']")
			if generals.size > 0
				general = Nokogiri::XML::Node.new("generalization", outputxml)
				outElem.add_child general
				generals.each do |child|
					childElem = newElement(inxml, child, outputxml, nil)
					if childElem != nil
						general.add_child childElem
					end
				end
			end
			
	end
	return outElem
end

outputxml = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') { |xml| 
	xml.UModel(:version => "9") {
		xml.Model {
			xml.Package(:uuid => "00000001-7510-11d9-86f2-000476a22f44", :name => "Root", :visibility => "public") {
				xml.packagedElement {
					xml.Package(:uuid => "00000003-7510-11d9-86f2-000476a22f44", :name => "Component View", :visibility => "public") 
				}
			}
		}
	}
}.doc

pe = outputxml.xpath("//packagedElement").first
model = inxml.xpath('//Model')[0]
children = model.xpath("./*")
for child in children
	# UModel requires profile application for all contexts so if none provided add the defaults
	if (child.attribute_with_ns('type',$xmiNS.href).to_s == "uml:Package") && (child["href"] == nil)
		pas = child.xpath("./profileApplication")
		if pas.size == 0
			#SysML
			pa = Nokogiri::XML::Node::new("profileApplication", inxml)
			pa["type"] = "uml:ProfileApplication"
			pa.attributes()['type'].namespace = $xmiNS
			pa["uuid"] = getOldUUID(child.attributes["uuid"].to_s,"profileApplication/ProfileApplication[1]")
			pa.attributes()['uuid'].namespace = $xmiNS
			ap = Nokogiri::XML::Node::new("appliedProfile", inxml)
			ap["type"] = "uml:Profile"
			ap.attributes()['type'].namespace = $xmiNS
			ap["href"] = 'http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0'
			pa.add_child ap
			child.add_child pa
			#PLCS
			pa = Nokogiri::XML::Node::new("profileApplication", inxml)
			pa["type"] = "uml:ProfileApplication"
			pa.attributes()['type'].namespace = $xmiNS
			pa["uuid"] = getOldUUID(child.attributes["uuid"].to_s,"profileApplication/ProfileApplication[3]")
			pa.attributes()['uuid'].namespace = $xmiNS
			ap = Nokogiri::XML::Node::new("appliedProfile", inxml)
			ap["type"] = "uml:Profile"
			ap.attributes()['type'].namespace = $xmiNS
			if isIndex
				ap["href"] = '..\PLCS-profile.xmi#_17_0_3_2b2015d_1328548545165_581012_11820'
			else
				ap["href"] = '..\..\..\PLCS-profile.xmi#_17_0_3_2b2015d_1328548545165_581012_11820'
			end
			pa.add_child ap
			child.add_child pa
		end
	end
	
	tpOut = newElement(inxml, child, outputxml, nil)
	if tpOut != nil
		pe.add_child tpOut
	end
end
# SysML and UML Profiles for application to the packages - should be automated from the XMI
# NOTE : although the SysML Profile will automatically drag in the UML Profile, both are required as ProfileApplication entries
#        which is not handled automatically.
sysmlProfile = Nokogiri::XML::Node.new("Profile", outputxml)
sysmlProfile["href"] = "SysML Profile.ump#411fec0d-7aac-4cb3-9dae-f7d7cd254301" 
sysmlProfile["editable"] = "false"
pe.add_child sysmlProfile
umlProfile = Nokogiri::XML::Node.new("Profile", outputxml)
umlProfile["href"] = "UML Standard Profile.ump#00000101-7510-11d9-86f2-000476a22f44" 
umlProfile["editable"] = "false"
pe.add_child umlProfile

File.open(output_file,"w"){|file| outputxml.write_xml_to file} 

stime = Time.now
puts 'END ' + stime.to_s
