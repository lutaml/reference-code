#!/usr/bin/env ruby
path = File.expand_path File.dirname(__FILE__) 
require 'nokogiri'
require path + '/../Ruby/sysml'
require 'uuid'
require 'pathname'
include Nokogiri
include SYSML
## Canonical XMI to Eclipse UML Model framework
## Version 0.2
## 2014-02-19
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
		puts "to_eclipse Version 0.2"
		puts " "
		puts "Usage parameters : xmi=<sysml.xmi>"
		puts " "
		puts "  <sysml.xmi> required input SysML XMI file"				
		exit
	end
end

if xmi_input_file == " "
	puts "to_eclipse Version 0.2"
	puts " "
	puts "ERROR : No XMI input"
	puts "Usage parameters : xmi=<sysml.xmi>"
	exit
end
if FileTest.exist?(xmi_input_file) != true
	puts "to_eclipse Version 0.2"
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
	puts "to_eclipse Version 0.2"
	puts " "
	puts "ERROR : File contains no 'xmi:XMI' XML elements :  #{xmi_input_file}, may not be XMI file."
	xmifile.close
	exit
end

#find the local packages
pkgs = inxml.xpath('//packagedElement[@xmi:type="uml:Package" and not(@href)]')
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
	if topPackages.size == 0
		profiles = inxml.xpath('//packagedElement[@xmi:type="uml:Profile" and not(@href)]')
		if profiles.size == 1
			filetype = 'profile'
			output_fileName = input_fileName
			inTop = profiles[0]
		else
			puts "Only one profile definition per xmi file can be handled!"
			exit
		end
	else
		output_fileName = input_fileName
		inTop = inxml.xpath("//uml:Model").first
	end
else
	filetype = 'plcslib'
	for tplpkg in tplpkgs
		innerPackages = tplpkg.xpath("./* [@name]") 
		# A template
		if innerPackages.size == 1
			if $outPackage == ""
				plcstype = 'template'
				$outPackage = innerPackages[0]["name"]
				output_fileName = $outPackage
				inTop = innerPackages[0]
			else
				puts "Found multiple output candidates " + $outPackage + " and " + innerPackages[0]["name"]
				exit
			end
		end
	end
  dxpkgs = pkgs.select {|x| x["name"] == "DEXs"}
	for dxpkg in dxpkgs
		innerPackages = dxpkg.xpath("./* [@name]") 
		# A DEX
		if innerPackages.size == 1
			if $outPackage == ""
				plcstype = 'dex'
				$outPackage = innerPackages[0]["name"]
				output_fileName = $outPackage
				inTop = innerPackages[0]
			else
				puts "Found multiple output candidates " + $outPackage + " and " + innerPackages[0]["name"]
				exit
			end
		end
	end
	# a context index
	if $outPackage == ""
		plcstype = 'index'
		output_fileName = "index"
		contextName = xmiInputPath.basename.to_s
		inTop = inxml.xpath("//uml:Model").first
	end	
end

$basePath = xmiInputPath + "dvlp"

Dir.chdir($basePath)

output_file = output_fileName + ".uml"
puts "Generating : dvlp\\" + output_file

if File.exists?(output_file)
	oldfile = File.open(output_file)
	$oldxml = Nokogiri::XML(oldfile, &:noblanks)
	oldfile.close
end

def getOld(path, attrib)
	if $oldxml != nil
		element = $oldxml.xpath(path).first
		if element != nil
			return element.attributes()[attrib]
		end
	end
	if attrib == 'id'
		return $uuid.generate
	end
end

case filetype
	when 'profile'
		NS = {
			"xmi:version"            => "20110701",
			"xmlns:xmi"               => "http://www.omg.org/spec/XMI/20110701",
			"xmlns:ecore"            => "http://www.eclipse.org/emf/2002/Ecore",
			"xmlns:uml"               => "http://www.eclipse.org/uml2/4.0.0/UML",
			"xmi:id"                    => inTop.attributes()['id'],
			"name"                       => inTop["name"]
		}

		nsURI = getOld("/uml:Profile/eAnnotations[1]/contents","nsURI")
		if nsURI == nil
			nsURI = "http:///schemas/"+inTop["name"]+"/"+$uuid.generate+"/0"
		end
		$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
			xml.Profile(NS) {
				xml.eAnnotations("xmi:type" => "ecore:EAnnotation", 
																"xmi:id"    => getOld("/uml:Profile/eAnnotations[1]", 'id'), 
																"source"    => "http://www.eclipse.org/uml2/2.0.0/UML") {
					xml.contents("xmi:type" => "ecore:EPackage", 
														"xmi:id"    => getOld("/uml:Profile/eAnnotations[1]/contents", 'id'), 
														"name"       => inTop["name"], 
														"nsURI"      => nsURI, 
														"nsPrefix" => inTop["name"]) {
						xml.eAnnotations("xmi:type" => "ecore:EAnnotation", 
																		"xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations", 'id'),
																		"source" => "PapyrusVersion") {
							xml.details("xmi:type" => "ecore:EStringToStringMapEntry",
														 "xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations/details[1]", 'id'),
														 "key" => "Version",
														 "value" => "0.0.1")
							xml.details("xmi:type" => "ecore:EStringToStringMapEntry",
														 "xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations/details[2]", 'id'),
														 "key" => "Comment",
														 "value" => "")
							xml.details("xmi:type" => "ecore:EStringToStringMapEntry",
														 "xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations/details[3]", 'id'),
														 "key" => "Copyright",
														 "value" => "")
							xml.details("xmi:type" => "ecore:EStringToStringMapEntry",
														 "xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations/details[4]", 'id'),
														 "key" => "Date",
														 "value" => "2013-09-26")
							xml.details("xmi:type" => "ecore:EStringToStringMapEntry",
														 "xmi:id" => getOld("/uml:Profile/eAnnotations[1]/contents/eAnnotations/details[5]", 'id'),
														 "key" => "Author",
														 "value" => "")
						}
					}
				}
			}
		}.doc
		$outTop = $outputxml.xpath("//Profile").first
		outTopPath = "/uml:Profile"
	when 'plcslib'
		NS = {
			"xmi:version"            => "20110701",
			"xmlns:xmi"               => "http://www.omg.org/spec/XMI/20110701",
			"xmlns:xsi"               => "http://www.w3.org/2001/XMLSchema-instance",
			"xmlns:Blocks"          => "http://www.eclipse.org/papyrus/0.7.0/SysML/Blocks",
			"xmlns:Constraints"  => "http://www.eclipse.org/papyrus/0.7.0/SysML/Constraints",
			"xmlns:PortAndFlows" => "http://www.eclipse.org/papyrus/0.7.0/SysML/PortAndFlows",
			"xmlns:ecore"            => "http://www.eclipse.org/emf/2002/Ecore",
			"xmlns:uml"               => "http://www.eclipse.org/uml2/4.0.0/UML",
			"xsi:schemaLocation" => "http://www.eclipse.org/papyrus/0.7.0/SysML/Blocks http://www.eclipse.org/papyrus/0.7.0/SysML#//blocks " +
																						"http://www.eclipse.org/papyrus/0.7.0/SysML/Constraints http://www.eclipse.org/papyrus/0.7.0/SysML#//constraints " +
																						"http://www.eclipse.org/papyrus/0.7.0/SysML/PortAndFlows http://www.eclipse.org/papyrus/0.7.0/SysML#//portandflows"
		}

		if plcstype == 'index'
			$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
				xml.XMI(NS) {
					xml.Model(:name => "SysMLmodel") {
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" =>getOld("//uml:Model/profileApplication[1]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[1]/eAnnotations", 'id'),
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#/")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_TZ_nULU5EduiKqCzJMWbGw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[2]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[2]/eAnnotations", 'id'),
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//blocks")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_fSw28LX7EduFmqQsrNB9lw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[3]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[3]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//constraints")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_5WYJ0LX7EduFmqQsrNB9lw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[4]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[4]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//portandflows")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_rpx28LX7EduFmqQsrNB9lw")
						}
					}
				}
			}.doc
			$outTop = $outputxml.xpath("//Model").first
			outTopPath = "/xmi:XMI/uml:Model"
		else
			$outputxml = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
				xml.XMI(NS) {
					xml.Package("name" => inTop["name"], "xmi:id" => inTop.attributes()['id']) {
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Package/profileApplication[1]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Package/profileApplication[1]/eAnnotations[1]", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#/")
							}
							xml.eAnnotations("xmi:id" => getOld("//uml:Package/profileApplication[1]/eAnnotations[2]", 'id'), "source" => "duplicatedProfile") 
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_TZ_nULU5EduiKqCzJMWbGw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Package/profileApplication[2]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Package/profileApplication[2]/eAnnotations[1]", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//blocks")
							}
							xml.eAnnotations("xmi:id" => getOld("//uml:Package/profileApplication[2]/eAnnotations[2]", 'id'), "source" => "duplicatedProfile") 
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_fSw28LX7EduFmqQsrNB9lw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Package/profileApplication[3]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Package/profileApplication[3]/eAnnotations[1]", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//constraints")
							}
							xml.eAnnotations("xmi:id" => getOld("//uml:Package/profileApplication[3]/eAnnotations[2]", 'id'), "source" => "duplicatedProfile") 
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_5WYJ0LX7EduFmqQsrNB9lw")
						}
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Package/profileApplication[4]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Package/profileApplication[4]/eAnnotations[1]", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//portandflows")
							}
							xml.eAnnotations("xmi:id" => getOld("//uml:Package/profileApplication[4]/eAnnotations[2]", 'id'), "source" => "duplicatedProfile") 
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_rpx28LX7EduFmqQsrNB9lw")
						}
					}
				}
			}.doc
			$outTop = $outputxml.xpath("//Package").first
			outTopPath = "/xmi:XMI/uml:Package"
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
				xml.Model(:name => "SysMLmodel") {
					xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[1]", 'id')) {
						xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[1]/eAnnotations", 'id'), 
																		"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
							xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#/")
						}
						xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_TZ_nULU5EduiKqCzJMWbGw")
					}
					xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[2]", 'id')) {
						xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[2]/eAnnotations", 'id'), 
																		"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
							xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/uml2/4.0.0/UML/Profile/L2#/")
						}
						xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://UML_PROFILES/StandardL2.profile.uml#_0")
					}
					if blocksNSneeded
						paCount = paCount + 1
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//blocks")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_fSw28LX7EduFmqQsrNB9lw")
						}
					end
					if constraintsNSneeded
						paCount = paCount + 1
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//constraints")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_5WYJ0LX7EduFmqQsrNB9lw")
						}
					end
					if moElNSneeded
						paCount = paCount + 1
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//modelelements")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_Gx8MgLX7EduFmqQsrNB9lw")
						}
					end
					if portsNSneeded
						paCount = paCount + 1
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//portsandflows")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_rpx28LX7EduFmqQsrNB9lw")
						}
					end
					if reqsNSneeded
						paCount = paCount + 1
						xml.profileApplication("xmi:type" => "uml:ProfileApplication", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]", 'id')) {
							xml.eAnnotations("xmi:type" => "ecore:EAnnotation", "xmi:id" => getOld("//uml:Model/profileApplication[" + paCount.to_s + "]/eAnnotations", 'id'), 
																			"source" => "http://www.eclipse.org/uml2/2.0.0/UML") {
								xml.references("xmi:type" => "ecore:EPackage", "href" => "http://www.eclipse.org/papyrus/0.7.0/SysML#//requirements")
							}
							xml.appliedProfile("xmi:type" => "uml:Profile", "href" => "pathmap://SysML_PROFILES/SysML.profile.uml#_OOJC4LX8EduFmqQsrNB9lw")
						}
					end
				}
			}
		}.doc
		$outTop = $outputxml.xpath("//Model").first
		outTopPath = "/xmi:XMI/uml:Model"
end

$file_hash = Hash.new
$uuid_hash = Hash.new
$profiles = Hash.new

inxml.root.add_namespace_definition("xmi","http://www.omg.org/spec/XMI/20110701")

$outxmiNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="xmi"}
outBlocksNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="Blocks"}
outConstraintsNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="Constraints"}
outMoElNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="ModelElements"}
outPortsNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="PortAndFlows"}
outReqsNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="Requirements"}
outL2NS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="l2"}

def getHref(href, eCore)
	hrefparts = href.split("#")
	filepath = hrefparts[0]
	id = hrefparts[1]
	if filepath.length == 0
		return id
	else
		newfilepath = $file_hash[filepath+eCore.to_s]
		if newfilepath == nil
			if filepath.index('http:') == 0
				filepathparts = filepath.split("/")
				indx = filepathparts.size - 1
				filename = filepathparts[indx]
				case filename
					when 'SysML-profile.uml'
						if eCore
							newfilepath = 'http://www.eclipse.org/papyrus/0.7.0/SysML#'
						else
							newfilepath = 'pathmap://SysML_PROFILES/SysML.profile.uml#'
						end
					else
						puts 'Unknown standard href path: ' + filename
				end
			else
				filepathname = Pathname.new('../' + filepath)
				dir = filepathname.dirname.realpath
				base = filepathname.basename(".xmi")
				filepathname = dir.relative_path_from($basePath) + "dvlp" + base
				newfilepath = filepathname.to_s  + ".uml#"
			end
			$file_hash[filepath+eCore.to_s] = newfilepath
		end	
		case newfilepath
			when 'pathmap://SysML_PROFILES/SysML.profile.uml#'
				case id
					when '_0'
					 id = '_TZ_nULU5EduiKqCzJMWbGw'
					when 'Block'
					 id = '_8J2A8LVAEdu2ieF4ON8UjA'
					else
						puts 'Unknown id :' + id
				end
			when 'http://www.eclipse.org/papyrus/0.7.0/SysML#'
				case id
					when 'Block'
					 id = '//blocks/Block'
					else
						puts 'Unknown id :' + id
				end
		end
		return newfilepath + id
	end
end	

def myCopy(obj, path)
	newObj = Nokogiri::XML::Node.new(obj.name, $outputxml)
	## extend annotations for eclipse	
	case obj.name
		when 'packagedElement'
			if (obj.attributes()['type'].to_s == 'uml:Stereotype')
				contents = $outTop.xpath("//eAnnotations/contents").first
				contentsPath = path+"/eAnnotations/contents"
				classfr = Nokogiri::XML::Node.new("eClassifiers",$outputxml)
				classfr['xmi:type'] = "ecore:EClass"
				classfr['xmi:id'] = getOld(contentsPath+classfr.path, 'id')
				classfr['name'] = obj['name']
				annot = Nokogiri::XML::Node.new("eAnnotations",$outputxml)
				annot['xmi:type'] = "ecore:EAnnotation"
				annot['xmi:id'] = getOld(contentsPath+classfr.path+annot.path, 'id')
				annot['source'] = "http://www.eclipse.org/uml2/2.0.0/UML"
				annot['references'] = obj.attributes()['id'].to_s
				general = obj.xpath("//generalization//general").first
				if general != nil
					superType = Nokogiri::XML::Node.new("eSuperTypes",$outputxml)
					superType['xmi:type'] = "ecore:EClass"
					superType['href'] = getHref(general['href'], true)
					classfr.add_child superType
				end
				classfr.add_child annot
				contents.add_child classfr
			end
		when 'profileApplication'
			for attr in obj.attribute_nodes
				if attr.name == "uuid"
					content = $profiles[attr.value.to_s]
					annot = Nokogiri::XML::Node.new("eAnnotations",$outputxml)
					annot['xmi:type'] = "ecore:EAnnotation"
					annot['xmi:id'] = getOld(path+newObj.path+annot.path, 'id')
					annot['source'] = "http://www.eclipse.org/uml2/2.0.0/UML"
					reference = Nokogiri::XML::Node.new("references",$outputxml)
					reference['xmi:type'] = "ecore:EPackage"
					href = obj.at("appliedProfile")["href"].to_s
					newhref = getHref(href, false)
					hrefparts = newhref.split("#")
					id = content.attributes()['id']
					reference['href'] = hrefparts[0] + '#' + id
					annot.add_child reference
					newObj.add_child annot
					attr.name = "id"
				end
			end
	end
		
	for attr in obj.attribute_nodes
		case attr.name
			when "href"
				newObj[attr.name] = getHref(attr.value, false)
			when "uuid"
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
			newChild = myCopy(child, path+newObj.path)
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

## remove isAtomic attribute from flow ports
flowports = inTop.xpath("//sysml:FlowPort")
for flowport in flowports
	if flowport.attributes["isAtomic"] != nil
		flowport.attributes["isAtomic"].remove
	end
end

## change case of requirement attributes
reqs = inTop.xpath("//sysml:Requirement")
for req in reqs
	req["id"] = req["Id"]
	req.attributes["Id"].remove
	req["text"] = req["Text"]
	req.attributes["Text"].remove
end

## remove profiles as packaged elements
profiles = inTop.xpath(".//packagedElement [@xmi:type='uml:Profile' and (@href)]" )
for profile in profiles
	profile.remove
end

## identify any unknown profile applications
pas = inTop.xpath("//profileApplication")
for pa in pas
	href = pa.at("appliedProfile")["href"].to_s
	if href != "http://www.omg.org/spec/SysML/20100301/SysML-profile.uml#_0"
		if href.index('http:') == 0
			puts "Unknown standard profile applied: " + href
		else
			hrefparts = href.split("#")
			id = hrefparts[1]
			filepath = Pathname.new("../" + hrefparts[0])
			dir = filepath.dirname + "dvlp"
			base = filepath.basename(".xmi").to_s + ".uml"
			filepath = dir + base
			newhref = getHref(href, false)
			newhrefparts = newhref.split("#")
			## add namespace
			otherfile = File.new(filepath, "r")
			otherxml = Nokogiri::XML(otherfile)
			prof = otherxml.xpath("//*[@xmi:id='" + id + "']").first
			content = prof.xpath("//eAnnotations/contents").first
			$outputxml.root.add_namespace_definition(prof["name"], content["nsURI"])
			## add to profiles
			$profiles[pa.attributes()["uuid"].to_s] = content
			## add to schemaLocation
			$outputxml.root["xsi:schemaLocation"] = $outputxml.root.attributes()["schemaLocation"].to_s + " " + content["nsURI"] + " " + newhrefparts[0] + "#" + content.attributes()['id']
		end
	else
		pa.remove
	end
end

## copy model over changing xmi namespace
children = inTop.xpath("./*")
firstchild = $outTop.children.first
for child in children
  childCopy = myCopy(child, outTopPath)
	if firstchild != nil
		firstchild.add_previous_sibling childCopy
	else
		$outTop.add_child childCopy
	end
end

## copy any sysml nodes over changing sysml and xmi namespaces
sysmlObjs = inxml.xpath("//sysml:*")
for sysmlObj in sysmlObjs
	sysmlCopy = myCopy(sysmlObj, "/xmi:XMI")
	$outTop.parent.add_child sysmlCopy
	case sysmlObj.name
		when "Block", "ValueType", "NestedConnectorEnd", "BindingConnector"
			sysmlCopy.namespace = outBlocksNS
		when "FlowPort"
			sysmlCopy.namespace = outPortsNS
		when "ConstraintBlock", "ConstraintProperty"
			sysmlCopy.namespace = outConstraintsNS
		when "Requirement"
			sysmlCopy.namespace = outReqsNS
		when "Rationale"
			sysmlCopy.namespace = outMoElNS
		else
			puts "SysML stereotype not handled: " + sysmlObj.name
	end
end

## copy any L2 nodes over changing L2 and xmi namespaces
inStdNS = inxml.root.namespace_definitions.find{|ns|ns.prefix=="StandardProfileL2"}
if inStdNS != nil
	l2Objects = inxml.xpath("//StandardProfileL2:*")
	for l2Object in l2Objects
		newObj = myCopy(l2Object, "/xmi:XMI")
		$outTop.parent.add_child newObj
		newObj.namespace = outL2NS
	end
end

## copy over any profile based nodes
$profiles.each_value {|value| 
  prefix = value["nsPrefix"]
	outprefNS = $outputxml.root.namespace_definitions.find{|ns|ns.prefix==prefix}
	prefObjects = inxml.xpath("//"+prefix+":*")
	for prefObject in prefObjects
		newObj = myCopy(prefObject, "/xmi:XMI")
		$outTop.parent.add_child newObj
		newObj.namespace = outprefNS
	end
}

$outTop['xmi:id'] = inTop.attributes()['id']
$outTop.namespace = $outputxml.root.namespace_definitions.find{|ns|ns.prefix=="uml"}
$outTop.parent.namespace = $outxmiNS

File.open(output_file,"w"){|file| $outputxml.write_xml_to file} 

if !File.exists?(output_fileName+".notation")
	notationId = $uuid.generate
	case filetype
		when 'profile'
			Dname = "Profile"
			Dtype = "PapyrusUMLProfileDiagram"
		when 'plcslib'
			Dname = plcstype
			Dtype = "BlockDefinition"
		else
			Dname = "NewDiagram"
			if blocksNSneeded
				Dtype = "BlockDefinition"
			elsif reqsNSneeded
				Dtype = "RequirementDiagram"
			else
				Dtype = "PackageDiagram"
			end
	end

	if $outTop.namespace != nil
		elemType = $outTop.namespace.prefix + ':' + $outTop.name
	else
		elemType = $outTop.name
	end

	nNS = {
		"xmi:version"            => "2.0",
		"xmlns:xmi"               => "http://www.omg.org/XMI",
		"xmlns:notation"       => "http://www.eclipse.org/gmf/runtime/1.0.2/notation",
		"xmlns:uml"               => "http://www.eclipse.org/uml2/3.0.0/UML",
		"xmi:id"                    => notationId,
		"type"                       => Dtype,
		"name"                       => Dname,
		"measurementUnit"      => "Pixel"
	}
	outputNotn = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
		xml.Diagram(nNS) {
			xml.styles("xmi:type" => "notation:DiagramStyle", "xmi:id" =>  $uuid.generate)
			xml.element("xmi:type" => elemType, "href" => output_fileName + ".uml#" + inTop.attributes()['id'])
		}
	}.doc
	outputNotn.root.namespace = outputNotn.root.namespace_definitions.find{|ns|ns.prefix=="notation"}
	File.open(output_fileName+".notation","w"){|file| outputNotn.write_xml_to file} 
end

if !File.exists?(output_fileName+".di")
	if (filetype == 'plcslib') && (plcstype == 'index')
		dNS = {
			"xmi:version"            => "2.0",
			"xmlns:xmi"               => "http://www.omg.org/XMI",
			"xmlns:xsi"               => "http://www.w3.org/2001/XMLSchema-instance",
			"xmlns:di"                 => "http://www.eclipse.org/papyrus/0.7.0/sashdi",
			"xmlns:history"         => "http://www.eclipse.org/papyrus/0.7.0/controlmode"
		}
		outputdi = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
			xml.XMI(dNS) {
				xml.SashWindowsMngr {
					xml.pageList 
					xml.sashModel("currentSelection" => "//@sashModel/@windows.0/@children.0") {
						xml.windows {
							xml.children("xsi:type" => "di:TabFolder") {
								xml.children {
									xml.emfPageIdentifier("href" => output_fileName + '.notation#' + notationId)
								}
							}
						}
					}
				}
			}
		}.doc
		outputdi.root.namespace = outputdi.root.namespace_definitions.find{|ns|ns.prefix=="xmi"}
		pagelist = outputdi.xpath("//pageList").first
		pagelist.parent.namespace = outputdi.root.namespace_definitions.find{|ns|ns.prefix=="di"}
		umlfiles = Nokogiri::XML::Node.new("ControledResource",outputdi)
		umlfiles["resourceURL"] = output_file
		notfiles = Nokogiri::XML::Node.new("ControledResource",outputdi)
		notfiles["resourceURL"] = output_fileName + '.notation'
		cntxpkg = pkgs.select {|x| x["name"] == contextName}.first
		pkgs = cntxpkg.xpath('*/packagedElement[@xmi:type="uml:Package" and(@href)]')
		for pkg in pkgs
			href = getHref(pkg["href"], false)
			hrefparts = href.split("#")
			filepath = hrefparts[0]
			children = Nokogiri::XML::Node.new("children",outputdi)
			children["resourceURL"] = filepath
			umlfiles.add_child children
			filepathname = Pathname.new(filepath)
			dir = filepathname.dirname
			base = filepathname.basename(".uml")
			filepathname = dir + base
			newfilepath = filepathname.to_s  + ".notation"
			children = Nokogiri::XML::Node.new("children",outputdi)
			children["resourceURL"] = newfilepath
			notfiles.add_child children
			if File.exists?(newfilepath)
				oldfile = File.open(newfilepath)
				oldxml = Nokogiri::XML(oldfile, &:noblanks)
				oldfile.close
				oldElem = oldxml.xpath('//notation:Diagram').first
				ap = Nokogiri::XML::Node.new("availablePage",outputdi)
				epi = Nokogiri::XML::Node.new("emfPageIdentifier",outputdi)
				epi["href"] = newfilepath + '#' + oldElem.attributes()['id']
				ap.add_child epi
				pagelist.add_child ap
			end
		end
		outputdi.root.add_child umlfiles
		umlfiles.namespace = outputdi.root.namespace_definitions.find{|ns|ns.prefix=="history"}
		outputdi.root.add_child notfiles
		notfiles.namespace = outputdi.root.namespace_definitions.find{|ns|ns.prefix=="history"}
	else
		dNS = {
			"xmi:version"            => "2.0",
			"xmlns:xmi"               => "http://www.omg.org/XMI",
			"xmlns:xsi"               => "http://www.w3.org/2001/XMLSchema-instance",
			"xmlns:di"                 => "http://www.eclipse.org/papyrus/0.7.0/sashdi"
		}
		outputdi = Nokogiri::XML::Builder.new(:encoding => "UTF-8") { |xml| 
			xml.SashWindowsMngr(dNS) {
				xml.pageList {
					xml.availablePage {
						xml.emfPageIdentifier("href" => output_fileName + '.notation#' + notationId)
					}
				}
				xml.sashModel("currentSelection" => "//@sashModel/@windows.0/@children.0") {
					xml.windows {
						xml.children("xsi:type" => "di:TabFolder") {
							xml.children {
								xml.emfPageIdentifier("href" => output_fileName + '.notation#' + notationId)
							}
						}
					}
				}
			}
		}.doc
		outputdi.root.namespace = outputdi.root.namespace_definitions.find{|ns|ns.prefix=="di"}
	end

	File.open(output_fileName+".di","w"){|file| outputdi.write_xml_to file} 
end

stime = Time.now
puts 'END ' + stime.to_s
