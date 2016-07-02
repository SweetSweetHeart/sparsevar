#' @export
fitVAR <- function(data, p = 1, penalty = "ENET", method = "cv", ...) {
  
  opt <- list(...)
  
  if (method == "cv") {
    
    out <- cvVAR(data, p, penalty, opt)
    
  } else if (method == "timeSlice") {
    
    out <- timeSliceVAR(data, p, penalty, opt)
  
  } else {
    
    stop("Unknown method. Possible values are \"cv\" or \"timeSlice\"")
  
  }
  
  return(out)
  
}

cvVAR <- function(data, p, penalty = "ENET", opt = NULL) {
  
  nc <- ncol(data)
  nr <- nrow(data)
  
  # transform the dataset
  trDt <- transformData(data, p, opt)
  
  if (penalty == "ENET") {
    
    # fit the ENET model
    t <- Sys.time()
    fit <- cvVAR_ENET(trDt$X, trDt$y, opt)
    elapsed <- Sys.time() - t
    
    # extract what is needed
    lambda <- ifelse(is.null(opt$lambda), "lambda.min", opt$lambda)
    
    # extract the coefficients and reshape the matrix
    Avector <- stats::coef(fit, s = lambda)
    A <- matrix(Avector[2:length(Avector)], nrow = nc, ncol = nc*p, byrow = TRUE)
    
    mse <- min(fit$cvm)
    
  } else if (penalty == "SCAD") {
    
    # convert from sparse matrix to std matrix (SCAD does not work with sparse matrices)
    trDt$X <- as.matrix(trDt$X)
    
    # fit the SCAD model
    t <- Sys.time()
    fit <- cvVAR_SCAD(trDt$X, trDt$y, opt)
    elapsed <- Sys.time() - t
    
    # extract the coefficients and reshape the matrix
    Avector <- stats::coef(fit, s = "lambda.min")
    A <- matrix(Avector[2:length(Avector)], nrow = nc, ncol = nc*p, byrow = TRUE)
    mse <- min(fit$cve)
    
  } else if (penalty == "MCP") {
    
    # convert from sparse matrix to std matrix (MCP does not work with sparse matrices)
    trDt$X <- as.matrix(trDt$X)
    
    # fit the MCP model
    t <- Sys.time()
    fit <- cvVAR_SCAD(trDt$X, trDt$y, opt)
    elapsed <- Sys.time() - t
    
    # extract the coefficients and reshape the matrix
    Avector <- stats::coef(fit, s = "lambda.min")
    A <- matrix(Avector[2:length(Avector)], nrow = nc, ncol = nc*p, byrow = TRUE)
    mse <- min(fit$cve)
    
  } else {
    
    # Unknown penalty error
    stop("Unkown penalty. Available penalties are: ENET, SCAD, MCP.")
    
  }
  
  # If threshold = TRUE then set to zero all the entries that are smaller than 
  # the threshold
  if (!is.null(opt$threshold)) {
    if (opt$threshold == TRUE) {
      tr <- 1 / sqrt(p*nc*log(nr))
      L <- abs(A) >= tr
      A <- A * L
    }
  }
  
  # Get back the list of VAR matrices (of length p)
  A <- splitMatrix(A, p)
  
  # Now that we have the matrices compute the residuals
  res <- computeResiduals(data, A)
  
  # Create the output
  output = list()
  output$mu <- trDt$mu
  output$A <- A
  
  # Do you want the fit?
  if (!is.null(opt$returnFit)) {
    if (opt$returnFit == TRUE) {
      output$fit <- fit
    }
  }
  
  # If ENET is used, return the lambda 
  if (penalty == "ENET") {
    output$lambda <- fit$lambda.min
  }
  
  output$mse <- mse
  output$time <- elapsed
  output$series <- trDt$series
  output$residuals <- res
  output$sigma <- cov(res)
  attr(output, "class") <- "var"
  attr(output, "type") <- "estimate"
  return(output)
}

cvVAR_ENET <- function(X, y, opt) {
  
  a  <- ifelse(is.null(opt$alpha), 1, opt$alpha)
  nl <- ifelse(is.null(opt$nlambda), 100, opt$nlambda)
  tm <- ifelse(is.null(opt$type.measure), "mse", opt$type.measure)
  nf <- ifelse(is.null(opt$nfolds), 10, opt$nfolds)
  parall <- ifelse(is.null(opt$parallel), FALSE, opt$parallel)
  ncores <- ifelse(is.null(opt$ncores), 1, opt$ncores)
  
  # Assign ids to the CV-folds (useful for replication of results)  
  if (is.null(opt$foldsIDs)) {
    foldsIDs <- numeric(0)
  } else {
    nr <- nrow(X)
    foldsIDs <- sort(rep(seq(nf), length = nr))
    # foldsIDs <- rep(seq(nf), length = nr)
  }
  
  if(parall == TRUE) {
    if(ncores < 1) {
      stop("The number of cores must be > 1")
    } else {
      # cl <- doMC::registerDoMC(cores = ncores) # using doMC as in glmnet vignettes
      cl <- doParallel::registerDoParallel(cores = ncores)
      if (length(foldsIDs) == 0) {
        cvfit <- glmnet::cv.glmnet(X, y, alpha = a, nlambda = nl, type.measure = tm, nfolds = nf, parallel = TRUE)
      } else {
        cvfit <- glmnet::cv.glmnet(X, y, alpha = a, nlambda = nl, type.measure = tm, foldid = foldsIDs, parallel = TRUE)
      }
    }
  } else {
    if (length(foldsIDs) == 0) {
      cvfit <- glmnet::cv.glmnet(X, y, alpha = a, nlambda = nl, type.measure = tm, nfolds = nf, parallel = FALSE)
    } else {
      cvfit <- glmnet::cv.glmnet(X, y, alpha = a, nlambda = nl, type.measure = tm, foldid = foldsIDs, parallel = FALSE)
    }
    
  }
  
  return(cvfit)
}

cvVAR_SCAD <- function(X, y, opt) {
  
  e <- ifelse(is.null(opt$eps), 0.01, opt$eps)
  nf <- ifelse(is.null(opt$nfolds), 10, opt$nfolds)
  parall <- ifelse(is.null(opt$parallel), FALSE, opt$parallel)
  ncores <- ifelse(is.null(opt$ncores), 1, opt$ncores)
  
  if(parall == TRUE) {
    if(ncores < 1) {
      stop("The number of cores must be > 1")
    } else {
      cl <- parallel::makeCluster(ncores)
      cvfit <- ncvreg::cv.ncvreg(X, y, nfolds = nf, penalty = "SCAD", eps = e, cluster = cl)
      parallel::stopCluster(cl)
    }
  } else {
    cvfit <- ncvreg::cv.ncvreg(X, y, nfolds = nf, penalty = "SCAD", eps = e)
  }
  
  return(cvfit)
  
}

cvVAR_MCP <- function(X, y, opt) {
 
  e <- ifelse(is.null(opt$eps), 0.01, opt$eps)
  nf <- ifelse(is.null(opt$nfolds), 10, opt$nfolds)
  parall <- ifelse(is.null(opt$parallel), FALSE, opt$parallel)
  ncores <- ifelse(is.null(opt$ncores), 1, opt$ncores)
  
  if(parall == TRUE) {
    if(ncores < 1) {
      stop("The number of cores must be > 1")
    } else {
      cl <- parallel::makeCluster(ncores)
      cvfit <- ncvreg::cv.ncvreg(X, y, nfolds = nf, penalty = "MCP", eps = e, cluster = cl)
      parallel::stopCluster(cl)
    }
  } else {
    cvfit <- ncvreg::cv.ncvreg(X, y, nfolds = nf, penalty = "MCP", eps = e)
  }
  
  return(cvfit)
  
}
