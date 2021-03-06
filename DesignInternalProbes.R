#to read in fasta files and create alignments, and design hybridization probes using primer3

#dependencies
#primer3 http://primer3.sourceforge.net/releases.php
#R libraries ShortRead, msa
#R function DesignProbeFunction.R

library(ShortRead); library(msa)
source("/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/DesignProbeFunction.R")  #get DesignProbe Function, modified from https://gist.github.com/al2na/8540391
WorkingDir="/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/MBON/Rockfish_COI"
	setwd(WorkingDir)
projectTitle="Rockfish"
#read left and right primers in, as previously designed by the pipeline
ampPrimers<-read.csv("/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/MBON/Rockfish_COI/primerResults_filtered_22bp_COI.csv", as.is=T)

#download relevant dataset as FASTA from nucleotide db, containing example taxa and counter-example taxa, from genbank
seqRequest="Sebastes jordani" #what taxonomic group do you want to download sequences for, that will include both ingroup and outgroup?
gene="COI" #COI, 16S, etc
nonTargetGene="18s"

#create and execute perl script for entrez query
query=paste0("$query = '\"", seqRequest,"\"[organism] NOT Bacteria[organism] AND mitochondrion[filter] AND (\"",gene,"\") NOT (\"", nonTargetGene,"\")';")
#query=paste("$query = '(\"16S\") AND mitochondrial AND \"Megaptera novaeangliae\"[organism] NOT Bacteria[organism] NOT genome';")
ncbidatabase="nucleotide"
format="fasta"  #"gb" , "fasta" , etc
outfilename=paste0(projectTitle,"_",gsub(" ","_", gene),".fasta")
qfile=readLines("/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/EntrezQuery_template.pl")
qfile[4]=query
qfile[9]=paste("$url = $base . \"esearch.fcgi?db=", ncbidatabase,"&term=$query&usehistory=y\";", sep="")
qfile[22]=paste0("open(OUT, \">", WorkingDir,"/",outfilename,"\") || die \"Can't open file!\\n\";", sep="")
qfile[30]=paste("        $efetch_url .= \"&retmax=$retmax&rettype=",format,"&retmode=text\";", sep="")
writeLines(qfile, "EntrezQuery.pl") #create perl script for query
system ("perl EntrezQuery.pl", intern=T)  #run query script and download from ncbi

#note: check fasta file by eye before continuing; you want to make sure it's the right gene region, etc., and edit accordingly

#read in fasta
fastaIn<-readFasta(paste0(WorkingDir,"/",outfilename))
seqsIn<-sread(fastaIn)  #create DNAstringSet

set.seed(97)
if(length(seqsIn)<51){seqAlign<-msa(seqsIn)} else {seqAlign<-msa(seqsIn[sample(1:length(seqsIn), 50)])} #here, sampling available sequences to align, for speed, and using the consensus of that alignment to test internal probes
consenSeq<-consensusString(seqAlign)

#trim ends and replace ambigs with N
consenSeq<-gsub("[-]", "", consenSeq)
consenSeq<-gsub("[^AGCT]", "N", consenSeq)

#check alignment of primers w consensus
pairwiseAlignment(consenSeq,ampPrimers[1,3], type="global")
pairwiseAlignment(consenSeq,as.character(reverseComplement(DNAString(ampPrimers[2,4]))), gapExtension=100, gapOpening=100, type="local")

designList=list(NA) #create list, each element of which will be the designed probes for a given set of input primers
for (i in 1:nrow(ampPrimers)){
	startPos<-1 #min(attributes(attributes(pairwiseAlignment(consenSeq,ampPrimers[i,3], gapExtension=100, gapOpening=100,type='local'))$pattern)$range) #primer1 binding site; minimum starting position for probe
	fragLength<-nchar(consenSeq) #ampPrimers$max_amplified_length[i] #max(attributes(attributes(pairwiseAlignment(consenSeq,as.character(reverseComplement(DNAString(ampPrimers[i,4]))), gapExtension=100, gapOpening=100, type="local"))$pattern)$range)-startPos # distance between primer 1 and primer2 binding site; max finishing position for probe	
	optTM<-((ampPrimers$Tm_primer_1[i]+ampPrimers$Tm_primer_2[i])/2)+9  #optimizing internal probe at 9deg above average amplification primer temp
	designList[[i]]<-DesignProbe(TargetSeq=as.character(consenSeq), name= projectTitle, primer1=ampPrimers[i,3], primer2=ampPrimers[i,4], startPos=startPos, fragLength = fragLength, optTM=optTM)
	if(is.wholenumber(i/10)){print(paste0("Trying Primer Set ",i," of ",nrow(ampPrimers)))}
}

which(!is.na(designList)) #primer sets for which a probe was found

pairwiseAlignment(consenSeq,ampPrimers[3,3], type="global")
pairwiseAlignment(consenSeq,as.character(reverseComplement(DNAString(ampPrimers[3,4]))), gapExtension=100, gapOpening=100, type="local")
pairwiseAlignment(seqAlign, designList[[3]][1,2], type="local") #check against consensus

#combine results from probe design with the input PCR primers, and create output dataframe 
ProbeResults<-ampPrimers[which(!is.na(designList)),]
	ProbeResults=data.frame(ProbeResults, as.data.frame(matrix(NA, nrow=nrow(ProbeResults), ncol=6)))
for (i in 1:nrow(ProbeResults)){ProbeResults[i,25:30]<-designList[!is.na(designList)][[i]][1,c(2,4,5,7:9)]}
	colnames(ProbeResults)[25:30]<-colnames(designList[!is.na(designList)][[i]][1,c(2,4,5,7:9)])

write.csv(ProbeResults, paste0("PrimerResults_w_Probes_",format(Sys.time(), "%Y_%m_%d_%X"),".csv"))

