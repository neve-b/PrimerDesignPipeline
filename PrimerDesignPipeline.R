#RPK August 2014; edited July 2016

#dependencies: 
#ecoPCR https://git.metabarcoding.org/obitools/ecopcr/wikis/home   
#ecoPrimers https://git.metabarcoding.org/obitools/ecoprimers/wikis/home
#NCBI taxdump.tar.gz ftp://ftp.cbi.edu.cn/pub/biomirror/taxonomy/ncbi/
#entrez query template document
#taxize R package   https://cran.r-project.org/web/packages/taxize/index.html

library(taxize)

WorkingDir="/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/MBON"
setwd(WorkingDir)

projectTitle="CommonMurre"

ecoPrimerspath="/Users/rpk/ecoPrimers/src"
ecoPCRpath="/Users/rpk/ecoPCR/src"
taxdumpPath="/Users/rpk/taxdump"
seqRequest="Alcidae" #what taxonomic group do you want to download sequences for, that will include both ingroup and outgroup?
target_taxon= as.numeric(get_ids("Uria aalge", db="ncbi")$ncbi)  #what taxon are you trying to amplify?
exclude_taxon= as.numeric(get_ids("Alle alle", db="ncbi")$ncbi)  #what taxonomic group are you trying NOT to amplify?


#download relevant dataset from nucleotide db, containing example taxa and counter-example taxa, from genbank
#create and execute perl script for entrez query
query=paste0("$query = '\"", seqRequest,"\"[organism] NOT Bacteria[organism] AND mitochondrion[filter]';")
#query=paste("$query = '(\"16S\") AND mitochondrial AND \"Megaptera novaeangliae\"[organism] NOT Bacteria[organism] NOT genome';")
ncbidatabase="nucleotide"
format="gb"  #"gb" , "fasta" , etc
outfilename=paste0(projectTitle,"_mt.gb")
qfile=readLines("/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/EntrezQuery_template.pl")
qfile[4]=query
qfile[9]=paste("$url = $base . \"esearch.fcgi?db=", ncbidatabase,"&term=$query&usehistory=y\";", sep="")
qfile[22]=paste0("open(OUT, \">", WorkingDir,"/",outfilename,"\") || die \"Can't open file!\\n\";", sep="")
qfile[30]=paste("        $efetch_url .= \"&retmax=$retmax&rettype=",format,"&retmode=text\";", sep="")
writeLines(qfile, "EntrezQuery.pl") #create perl script for query
system ("perl EntrezQuery.pl", intern=T)  #run query script and download from ncbi



#format database using ecoPCRFormat
infilename=paste(WorkingDir, "/", outfilename, sep="")
foldername=strsplit(basename(infilename), "\\.")[[1]][1]
dir.create(foldername)  #create folder for db files and move gb file into that folder
system(paste("mv", infilename, foldername, sep=" "))

#copy this script into new dir, so there's a record
thisScript="/Users/rpk/GoogleDrive/Kelly_Lab/Bioinformatics/PrimerDesign/PrimerDesignPipeline.R" #NOTE: this is hard-coded, because I couldn't figure out a better way to do it.  So you have to change it manually here.
system(paste0("cp ", thisScript, " ", foldername))
#rename script
system(paste0("mv ", foldername,"/", basename(thisScript)," ", foldername, "/",strsplit(basename(thisScript),"\\.")[[1]][1],"_", format(Sys.time(), "%H_%M_%S"),"_", projectTitle,".R"))

#run the formatting script
system(paste("cd ", strsplit(ecoPCRpath, "/src")[[1]][1],"/tools;./ecoPCRFormat.py  -g -n ", WorkingDir,"/",foldername, "/", outfilename," -t ",taxdumpPath," ", WorkingDir,"/",foldername, "/", outfilename,"*", sep=""))


#use ecoPrimers to design primers of relevant characteristics; Note odd notation of file location -- ecoPrimers wants the path and then the prefix of its files (e.g., those with extensions .sdx, .ndx, etc)
specificity=0.85 #the proportion of the target sequence records that must be good primer matches
quorum=0.7 #the proportion of the sequence records in which a strict match between the primers and their targets occurs (default: 0.7) [not obvious to me what this does if errors_allowed==0... or alternatively, if this means that the quorum proportion of records for the target species must all contain a given primer set, record sets containing a large number of different gene regions pose a significant problem here, and this parameter should be set low]
falsepositive=0 #the maximum proportion of the counterexample sequence records that fulfill the specified parameters for designing the barcodes and the primers
primer_length=22
errors_allowed=2
#note option -c considers the circularity of the genome (i.e., for mtDNA primers); I've put this in the call by default.
##note option -3 asks for the min number of perfect nucleotide matches on the 3prime end.  I've set this at 5 by defaut.

ecoPrimersheader=c("serial_number","primer1","primer2","Tm_primer_1","Tm_primer_1_w_mismatches","Tm_primer_2","Tm_primer_2_w_mismatches","C+G_primer_1","C+G_primer_2","good/bad","in_sequence_count","out_sequence_count","yule","in_taxa_count","out_taxa_count","coverage","Number_of_well_identified_taxa","specificity","min_amplified_length","max_amplified_length","avg_amplified_length")
database=paste(WorkingDir,"/",foldername, "/", outfilename, sep="")
EcoPrimersoutfile=paste(WorkingDir,"/",foldername, "/ecoPrimer_results_",format(Sys.time(), "%b_%d_%H:%M:%S"),".txt", sep="")
system(paste("cd ", ecoPrimerspath,";./ecoPrimers -d ",database," -l 100 -L 500 -e ",errors_allowed," -r ", target_taxon," -E ", exclude_taxon," -t species -s ",specificity," -q ",quorum,"-x ", falsepositive," -O ", primer_length,"-c -3 5 > ", EcoPrimersoutfile, sep=""))   

#read in results, with header, for easy visual inspection  [the default output from ecoPrimers isn't easily human-readable, because it doesn't have headers, but does save the params with which the program was run, which is helpful]
primerResults=read.table(EcoPrimersoutfile)
names(primerResults)=ecoPrimersheader

#FILTER primers for large differences in Tm between primers and for homopolymers
primerResults<-primerResults[abs(primerResults$Tm_primer_1-primerResults$Tm_primer_2)<10,]  #filter out if difference in Tm is greater than 10degrees
primerResults<-primerResults[primerResults$Tm_primer_1>40&primerResults$Tm_primer_1<60,]  #filter out if Tm greater than 60 or less than 40
primerResults<-primerResults[primerResults$Tm_primer_2>40&primerResults$Tm_primer_2<60,]  #filter out if Tm greater than 60 or less than 40
primerResults<-primerResults[-grep("A{4,}|C{4,}|T{4,}|G{4,}", primerResults$primer1),] #filter out homopolymers of length greater than 4
primerResults<-primerResults[-grep("A{4,}|C{4,}|T{4,}|G{4,}", primerResults$primer2),] #filter out homopolymers of length greater than 4
primerResults<-primerResults[order(primerResults[,"good/bad"], decreasing=T),] #sort so Good/Good primers will be first

#identify unique primer sequences for forward and reverse candidate primers
primerResults<-data.frame(match(primerResults$primer1, unique(primerResults$primer1)), primerResults); names(primerResults)[1:2]<-c("Primer1_ID","Primer2_ID")
primerResults[,2]<-match(primerResults$primer2, unique(primerResults$primer2))
head(primerResults)
write.csv(primerResults, paste0(foldername,"/primerResults_filtered_", primer_length,"bp.csv"), row.names=F)

###optional: create fasta file of primer results
writeLines(paste(">",foldername, "fwd", seq(1:dim(primerResults)[1]), "\r", as.character(primerResults[seq(1:dim(primerResults)[1]),2]),"\r", ">",foldername, "rev", seq(1:dim(primerResults)[1]), "\r", as.character(primerResults[seq(1:dim(primerResults)[1]),3]),"\r",sep=""), paste(WorkingDir,"/",foldername, "/ecoPrimer_results.fasta", sep=""))


#use ecoPCR to test for amplification of non-target taxa in database
ecoPCRheader=c("accession_number","sequence_length","taxonomic_id","rank","species_taxonomic_id","scientific_name","genus_taxonomic_id","genus_name","family_taxonomic_id","family_name","super_kingdom_taxonomic_id","super_kingdom_name","strand_(direct_or_reverse)","first_oligonucleotide","number_of_errors_for_the_first_strand","second_oligonucleotide","number_of_errors_for_the_second_strand","amplification_length","sequence_description")
database= database  #using database from above
ecoPCRoutfile=paste0(WorkingDir,"/",foldername,"/ecopcr.out")
primer1= as.character(primerResults$primer1[1])#"ACYCTAGGGATAACAGCGYAAT"##
primer2= as.character(primerResults$primer2[1])#"CCGGTCTGAACTCAGATCAYGT"##
#-e Maximum number of errors (mismatches) allowed per primer (default: 0)
#-c Considers that the sequences of the database are circular (e.g. mitochondrial or chloroplast DNA)
system(paste("cd ",ecoPCRpath,";./ecoPCR -d ",database," -l100 -L500 -e2 -k -c ",primer1," ",primer2," > ", ecoPCRoutfile, sep=""), intern=T)
temp=readLines(ecoPCRoutfile)
temp=gsub("###","<none>",temp)
writeLines(temp, ecoPCRoutfile)
results=read.table(ecoPCRoutfile, sep="|")
names(results)=ecoPCRheader
unique(results$genus_name)
#unique(results$super_kingdom_name)
#boxplot(number_of_errors_for_the_first_strand~ family_name, data=results)


#Double-check for reasonable GC content, 3' end binding affinity, etc.

#THEN, do alignment of a handful of target taxa from ecosystem of interest, and make sure primers that work in theory look like they'll work in practice.  Add ambiguities if absolutely necessary.  Then re-use ecoPCR w degenerate primers

`