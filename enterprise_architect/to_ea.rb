#!/usr/bin/env ruby
path = File.expand_path File.dirname(__FILE__) 
require path + '/../Ruby/sysml'
require 'erb'
include SYSML
## Canonical XMI to Enterprise Architect Controlled Package
## Version 0.1
## 2012-01-30
##
## MAIN PROCESS STARTS HERE
## Parse input options
##
xmi_input_file = " "
debug = TRUE
for arg in ARGV
	argarray = arg.split('=')
	if argarray[0] == "xmi"
		xmi_input_file = argarray[1]
	end
	
	if argarray[0] == "help" or argarray[0] == "-help" or argarray[0] == "--help" or argarray[0] == "-h" or argarray[0] == "--h"
		puts " Version 0.1"
		puts " "
		puts "Usage parameters : xmi=<sysml.xmi>"
		puts " "
		puts "  <sysml.xmi> required input SysML XMI file"				
		exit
	end
end
if xmi_input_file == " "
	puts "to_ea Version 0.1"
	puts " "
	puts "ERROR : No XMI input"
	puts "Usage parameters : xmi=<sysml.xmi>"
	exit
end
if FileTest.exist?(xmi_input_file) != true
	puts "to_ea Version 0.1"
	puts " "
	puts "ERROR : XMI input file not found : #{xmi_input_file}"
	exit
end
##
##  Set up XMI File and template output file
##
stime = Time.now
puts 'START ' + stime.to_s

sysmlFile = SysMLFile.new
sysmlFile.parse xmi_input_file

$file_hash = Hash.new
$dvlp_hash = Hash.new
$id_hash = Hash.new

EAFileStart = %{<?xml version="1.0" encoding="windows-1252"?>
<XMI xmi.version="1.1" xmlns:UML="omg.org/UML1.3">
	<XMI.header>
		<XMI.documentation>
			<XMI.exporter>Enterprise Architect</XMI.exporter>
			<XMI.exporterVersion>2.5</XMI.exporterVersion>
		</XMI.documentation>
	</XMI.header>
	<XMI.content>
		<UML:Model name="EA Model" xmi.id="MX_EAID_4E415810_6EE2_46e0_992D_4E5279926AF3">
			<UML:Namespace.ownedElement>
}

EAPackageStart = %{				<UML:Package name="<%= item.name %>" xmi.id="<%= item.xmi_id %>" isRoot="false" isLeaf="false" isAbstract="false" visibility="public">
					<UML:ModelElement.taggedValue>
						<% if parentId != nil %><UML:TaggedValue tag="parent" value="<%= parentId %>"/>
						<% end %><% if filepath != nil %><UML:TaggedValue tag="iscontrolled" value="TRUE"/>
						<UML:TaggedValue tag="xmlpath" value="<%= filepath %>"/>
						<% end %><UML:TaggedValue tag="version" value="1.0"/>
						<UML:TaggedValue tag="isprotected" value="FALSE"/>
						<UML:TaggedValue tag="usedtd" value="FALSE"/>
						<UML:TaggedValue tag="owner" value=""/>
						<UML:TaggedValue tag="xmiver" value="Enterprise Architect XMI/UML 1.3"/>
						<UML:TaggedValue tag="logxml" value="FALSE"/>
						<UML:TaggedValue tag="packageFlags" value="Recurse=0;VCCFG=PLCSlib.data;<% if item.kind_of? UML::Model %>CRC=0;isModel=1;<% end %>"/>
						<UML:TaggedValue tag="batchsave" value="0"/>
						<UML:TaggedValue tag="batchload" value="0"/>
						<UML:TaggedValue tag="phase" value="1.0"/>
						<UML:TaggedValue tag="status" value="Proposed"/>
						<UML:TaggedValue tag="author" value=""/>
						<UML:TaggedValue tag="complexity" value="1"/>
						<UML:TaggedValue tag="ea_stype" value="Public"/>
						<UML:TaggedValue tag="tpos" value="0"/>
						<UML:TaggedValue tag="gentype" value="Java"/>
					</UML:ModelElement.taggedValue>
}

EAPackageEnd = %{				</UML:Package>
}

EAFileEnd = %{</UML:Namespace.ownedElement>
		</UML:Model>
	</XMI.content>
	<XMI.difference/>
	<XMI.extensions xmi.extender="Enterprise Architect 2.5"/>
</XMI>}

$indexfile = File.new("dvlp\\EAIndex.xml", "w")

res = ERB.new(EAFileStart)
t = res.result(binding)
$indexfile.puts t

$template = sysmlFile.block_list[0].base_class
$context = $template.namespace.namespace.namespace

def GenPackage ( item, parentId )
	filepath = nil
	if item.href == nil
		if item.name == $template.name
			filepath = "contexts\\" + $context.name + "\\templates\\" + $template.name + "\\dvlp\\EA" + $template.name + ".xml"
		end
	else
		hrefparts = item.href.split('#')
		path = hrefparts[0]
		xmi_id = hrefparts[1]
		filepath = $file_hash[path]
		if filepath == nil
			path_parts = path.split('\\')	
			case path_parts.size
				when 3
					# Template in same context
					filename = "EA" + path_parts[1] + ".xml"
					filepath = "contexts\\" + $context.name + "\\templates\\" + path_parts[1] + "\\dvlp\\" + filename
					$file_hash[path] = filepath				
				when 7
					if path_parts[6] == "plcs_psm.xmi"
						# PLCS_PSM reference!
						filename = "EAplcs_psm.xml"
						filepath = "PLCS\\psm_model\\dvlp\\EAplcs_psm.xml"
						$file_hash[path] = filepath
					else
						# Template in another context
						filename = "EA" + path_parts[5] + ".xml"
						filepath = "contexts\\" + path_parts[3] + "\\templates\\" + path_parts[5] + "\\dvlp\\" + filename
						$file_hash[path] = filepath
					end
				else
					puts "Unexpected href: " + path
			end
			path_parts[path_parts.size - 1] = "dvlp"
			dvlp_path = path_parts.join('\\')
			$dvlp_hash[path] = dvlp_path
			#get name for href#id
			if File.exists? path
				xmifile = File.open(path)
				xmixml = Nokogiri::XML(xmifile)
				package = xmixml.xpath('//packagedElement[@xmi:type="uml:Package" and @xmi:id="' + xmi_id + '"]').first
				name = package["name"].to_s.strip
				puts name
				eapath = dvlp_path + "\\" + filename
				puts path
				puts eapath
				if File.exists? eapath
					puts "fileexists"
					eafile = File.open(eapath)
					eaxml = Nokogiri::XML(eafile)
					eapackage = eaxml.xpath('//UML:Package[@name="' + name + '"]').first
					item.xmi_id = eapackage["xmi.id"].to_s.strip
				else
					puts "cannot find : " + eapath
				end
			end			
		end		
	end
	
	res = ERB.new(EAPackageStart)
	t = res.result(binding)
	$indexfile.puts t
	
	if item != $template.namespace
		for subitem in item.contents
			if subitem.kind_of?  Package
				GenPackage( subitem, item.xmi_id )
			end
		end
	end
	
	res = ERB.new(EAPackageEnd)
	t = res.result(binding)
	$indexfile.puts t
end

for model in sysmlFile.model_list
	GenPackage( model, "MX_EAID_4E415810_6EE2_46e0_992D_4E5279926AF3" )
end

res = ERB.new(EAFileEnd)
t = res.result(binding)
$indexfile.puts t

$indexfile.close

stime = Time.now
puts 'END ' + stime.to_s
