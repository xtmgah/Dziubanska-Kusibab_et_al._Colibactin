run_sbs_hdp <- function(jobIndex) {
  # HDP single base substitution signature extraction by node.
  # conditioning on PCAWG.
  
  #jobIndex <- as.numeric(Sys.getenv("LSB_JOBINDEX"))
  setwd("/data_genome1/public_data/Stratton_crypt_signatures/git/colon_microbiopsies/signature_extraction/subsitutions_hdp_signature_extraction/")
  # to get the FARM job array index and use it for:
  # (a) randomisation seeds dependent on the job index,
  # (b) saving out results named by job index (in a .RData file containing hdpSampleChain object)
  
  library(hdp)
  
  # set random seed.
  randseed <- 33333*(jobIndex) + 1
  print(paste0("Job index:", jobIndex))
  print(paste0("Random seed:", randseed))
  
  # read in trinucleotides.
  tnt <- read.csv("sbs_category_counts.txt",
                  sep="\t", header = T, stringsAsFactors =F, row.names = 1)
  patients <- sapply(strsplit(rownames(tnt), ":"), "[[", 1)
  
  # read in PCAWG sigs
  sigs <- read.csv("PCAWG_sigProfiler_SBS_signatures.csv", header = T, row.names = 1, stringsAsFactors = F)
  
  # I only want to keep a subset of them. I am picking the ones that have been found in colorectal cancer, as documented in the PCAWG SBS vignette 2018.04.27, downloaded from synapse 2018.04.30
  # NB like in previous runs I am excluding MSI sigs and pole and AID here. If they are there they should be obvious and come out anyway.
  gdsigs <- c("SBS1", "SBS2", "SBS3", "SBS5", "SBS13", "SBS16", "SBS17a", "SBS17b", "SBS18", "SBS25", "SBS28", "SBS30", "SBS37", "SBS40", "SBS41", "SBS43", "SBS45", "SBS49") 
  sigs <- as.matrix(sigs[,gdsigs])
  
  prior_pseudoc <- rep(1000, ncol(sigs)) # this is meant to be a vector of pseudocounts contributed by each prior distribution.
  
  test_prior <- hdp_prior_init(sigs, prior_pseudoc, hh=rep(1, 96), alphaa=c(1, 1), alphab=c(1, 1))
  
  # add three more CPs for the data that we will add: 
  # one for the branch from the grandparent to the MRCA of the patients, 
  # one for all the branches from the MRCA of the patients to each patient
  # one to go from each patient to all their child nodes (same cp for all patients)
  test_prior <- hdp_addconparam(test_prior, alphaa=c(1,1,1), alphab=c(1,1,1))
  
  # now add the hierarchical structure of the dataset.
  # I want: 
  # ppindex 0 for the top node. - ALREADY PRESENT
  # ppindex 1 for each of the 28 signatures. - ALREADY PRESENT
  # ppindex 1 for the MRCA of all the patients. - TO ADD
  # ppindex 30 (i.e. the MRCA of all the patients) for all 42 patients. - TO ADD
  # and then each branch has the ppindex of the patient that it comes from. - TO ADD
  
  ptsmrcappindex <- 1
  ptsppindices <- rep(c(1 + ncol(sigs) + 1), length(unique(patients)))
  
  branchppindices <- as.numeric(unlist(sapply(unique(patients), function(patient) {
    tnum <- length(which(patients==patient))
    tindex <- (1 + ncol(sigs) + 1) + which(unique(patients)==patient)
    rep(tindex, tnum)
  })))
  
  newppindices <- c(ptsmrcappindex, ptsppindices, branchppindices)
  
  # For concentration parameters, give one for every level of the hierarchy:
  # cpindex 1 for the grandparent. - ALREADY PRESENT
  # cpindex 2 for all the signatures - ALREADY PRESENT
  # cpindex 3 for the parent of the patients - NEED TO ADD
  # cpindex 4 for all the patients - NEED TO ADD
  # cpindex 5 for all the patients to their branches - NEED TO ADD
  newcpindices <- c(3, rep(4, length(unique(patients))), rep(5, nrow(tnt)))
  
  # add dp nodes: 
  # one as the parent of all the patients
  # one for each of the 42 patients
  # one for every single branch.
  # i.e. this should be the same as the number of new ppindicies and cpindices
  test_prior <- hdp_adddp(test_prior,
                          numdp = length(newppindices),
                          ppindex = newppindices,
                          cpindex = newcpindices)
  
  # need to make sure that I am adding data in a way that matches the data to the terminal nodes.
  # dpindices are the indices of the terminal nodes. The first terminal node is number 73.
  test_prior <- hdp_setdata(hdp=test_prior, dpindex=(max(newppindices) + 1:nrow(tnt)), data=tnt)
  
  
  # run chain
  test_pr <- dp_activate(test_prior, dpindex=(1+ncol(sigs)+1):numdp(test_prior), initcc=(ncol(sigs)+round(ncol(sigs)/10)))
  test_chlist <- hdp_posterior(test_pr, burnin=500000, n=100, space=2000, cpiter=3, seed=randseed)
  
  # save data.
  assign(paste0("hdp_", jobIndex), test_chlist)
  
save(list=paste0("hdp_", jobIndex), file=paste0("hdpout_", jobIndex, ".RData"))
}

library(BiocParallel)
bpp = MulticoreParam(workers = 12)

rr = bplapply(as.list(1:10), run_sbs_hdp)


