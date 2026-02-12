suppressPackageStartupMessages({
    require(zoo)
    require(lubridate)
    require(kde1d)
    require(SPEI)
    require(Rmpfr)
    require(parallel)
})

# Non-parametric SPEI function         22.08.2023
np.spei <- function(x, scale, kernel = list(type = 'rectangular', shift = 0),
                    na.rm = FALSE, ref.start=NULL, ref.end=NULL,
                    window.half = 0, formula = NULL, data = NULL,
                    verbose=FALSE, estim = c("LLE", "ECDF", "GPP"),
                    family_set = "parametric", precBits=256,
                    jitter.type = c("jitter", "none"), seed=40,
                    xmin = NaN, xmax = NaN, deg = 2, precq=FALSE,
                    returnF = FALSE, time.frame=NULL)
{
  #message("===== STARTING np.spei FUNCTION =====")
  #message("Input x class: ", class(x))
  #message("Input x length: ", length(x))
  #if(length(x) > 0) message("Input x sample values: ", paste(head(x), collapse = ", "))
  
  # Checks
  xold <- x
  #message("Loading required packages...")
  require(zoo)
  require(lubridate)
  require(kde1d)
  require(SPEI)
  require(Rmpfr)
  
  if(!is.numeric(scale)) stop("scale needs to be numeric!")
  if((!is.null(ref.start) & is.null(ref.end)) | (is.null(ref.start) & !is.null(ref.end)))
    stop("ref.start and ref.end needs to be filled when used!")
  jitter.type <- match.arg(jitter.type)
  nn <- length(x)
  #message("Initial nn (length of x): ", nn)
  estim <- match.arg(estim)
  #message("Selected estim method: ", estim)
  
  # Bestimme Zeitattribute von x
  if(window.half == "bic") {
    #message("Calculating window.half using BIC...")
    window.half <- FitAR::SelectModel(as.numeric(x))[1,1]
    #message("window.half set to: ", window.half)
  }

  # Anpassung der Zeit -> 29. Februrar entfernen falls vorhanden
  if(is.null(time.frame)){
    #message("Processing without time.frame")
    if(is.ts(x)) {
      #message("Converting ts to zoo...")
      x <- as.zoo(x)
    }
    
    # Check if we have a zoo object
    if(is.zoo(x)) {
      #message("x is now a zoo object")
      xtest.day <- length(unique(day(x)))
      #message("Number of unique days: ", xtest.day)
      
      # 29 Februar für Bias entfernen
      if(xtest.day > 1) {
        #message("Checking for February 29...")
        xrm29 <- which(day(x) == 29 & month(x) == 2)
        #message("February 29 indices: ", paste(xrm29, collapse = ", "))
        if(length(xrm29) > 0) {
          #message("Removing February 29 entries")
          x <- x[-xrm29]
          #message("New x length: ", length(x))
        }
      }
    }
  } else {
    #message("Processing with time.frame")
    if(!any(colnames(time.frame) %in% c("day", "month", "year")))
      stop("colnames need to have the names day, month and year!")
    day.f.seq <- subset(time.frame, year == time.frame$year[1])$day
    mon.f.seq <- subset(time.frame, year == time.frame$year[1])$month
    xyears <- unique(time.frame$year)
  }

  # Kumullieren
  #message("Checking scale parameter: ", scale)
  if(scale > 1){
    #message("Applying accumulation with scale: ", scale)
    # Checks
    kernel.names <- names(kernel)
    if(kernel.names[1] != "type" | kernel.names[2] != "shift")
      stop("Kernel names need to be c(type, shift)!")
    
    #message("Calculating kernel weights...")
    wget <- SPEI::kern(scale, type = kernel$type, shift = kernel$shift)*scale
    #message("Kernel weights: ", paste(wget, collapse = ", "))
    
    #message("Applying rollapply...")
    x <- zoo::rollapply(x, width = scale, function(xx)sum(xx*rev(wget)),
                        fill = NA, align = "right")
    #message("After accumulation - x length: ", length(x))
    #if(length(x) > 0) message("x sample values after accumulation: ", paste(head(na.omit(x)), collapse = ", "))
  } 
  
  # Fitte für jeden Monat eine Verteilung
  if(!is.null(ref.start) & !is.null(ref.end)){
    if(length(ref.start) > 1) stop("Only year can be given for ref.start!")
    if(length(ref.end)   > 1) stop("Only year can be given for ref.end!")
    xyears.ref <- ref.start:ref.end 
  } else {
    xyears.ref <- unique(year(x))
  }
  #message("Reference years: ", paste(xyears.ref, collapse = ", "))

  xcyc <- cycle(x)
  #message("Unique cycle values: ", paste(unique(xcyc), collapse = ", "))
  spei.fin <- rep(NA, nn)
  
  #message("Starting monthly processing loop...")
  for(iindex in unique(xcyc)){
    #message("\nProcessing cycle index: ", iindex)
    
    # Daten extrahieren für Fall ohne fenster
    if(is.null(time.frame)) {
      index <- which(cycle(x) == iindex)
      #message("Index length for cycle ", iindex, ": ", length(index))
    } else {
      index <- which(time.frame$month == mon & time.frame$day == day)
    }
    index.orig <- index # Bei smoothing windows nötig
    
    if(window.half > 0){
      #message("Applying window adjustment with half-width: ", window.half)
      index <- sort(unlist(sapply(index, function(i){
        low <- max(1, i-window.half)
        up <- min(length(x), i+window.half)
        low:up
      }), use.names = FALSE))
      #message("After window adjustment - index length: ", length(index))
    } 
    
    # Anpassung der Zeit
    if(is.null(time.frame)){
      data.all.zoo <- x[index]
      data.all <- as.numeric(x)[index]
      #message("data.all length: ", length(data.all))
      #if(length(data.all) > 0) message("data.all sample: ", paste(head(data.all), collapse = ", "))
      
      index.ref <- which(year(x)[index] %in% xyears.ref)
      #message("index.ref length: ", length(index.ref))
      
      data.ref <- data.all[index.ref]
      #message("data.ref length: ", length(data.ref))
      #if(length(data.ref) > 0) message("data.ref sample: ", paste(head(data.ref), collapse = ", "))
      
      data.eval <- as.numeric(x)[index.orig]
      #message("data.eval length: ", length(data.eval))
      #if(length(data.eval) > 0) message("data.eval sample: ", paste(head(data.eval), collapse = ", "))
    } else {
      t.copy <- time.frame
      t.copy$index <- as.numeric(time.frame$month == mon & time.frame$day == day)
      t.use <- subset(t.copy, index==1)
      data.all <- as.numeric(x)[index]
      data.ref <- data.all[which(t.use$year %in% xyears.ref & t.use$month == mon & t.use$day==day)]
      data.eval <- as.numeric(x)[which(time.frame$month == mon & time.frame$day == day)]
    }

    # Für korrektur später muss hier nn abgespeichert werden
    nn <- length(data.eval)
    #message("Adjusted nn: ", nn)
    
    # Wegen kumullierung können NA´s auftreten, das muss angepasst werden
    Na.check <- any(is.na(data.eval))
    #message("NA check: ", Na.check)
    if(Na.check){
      data.is.na <- which(is.na(data.eval))
      #message("NA indices: ", paste(data.is.na, collapse = ", "))
      data.eval <- data.eval[-data.is.na]
      data.ref <- data.ref[-data.is.na]
      #message("After NA removal - data.eval length: ", length(data.eval))
      #message("After NA removal - data.ref length: ", length(data.ref))
    }
    
    # Hier Beginnt loop falls mehrer Daten vorhanden
    data.tab <- table(data.all)
    data.tab.num <- as.numeric(data.tab)
    #message("Data table summary: ", paste(summary(data.tab.num), collapse = "; "))
    
    if(all(data.tab.num == 1) | jitter.type == "none") {
      B <- 1 # Stetiger Fall
      is.discrete <- FALSE
    }
    else {
      #if(verbose) message("\nDiscrete values detected - resampling.")
      is.discrete <- TRUE
      set.seed(seed)
    }
    #message("B: ", B)
    #message("is.discrete: ", is.discrete)
    
    # Check auf mehrere Nullen
    if(is.discrete & jitter.type == "jitter"){
      #message("Applying jitter to discrete values...")
      disc.vals <- as.numeric(names(data.tab)[which(data.tab.num > 1)])
      #message("Discrete values: ", paste(disc.vals, collapse = ", "))
      disc.ind <- which(data.all %in% disc.vals)
      #message("Discrete indices count: ", length(disc.ind))
      
      if(length(disc.ind) == length(data.all)) {
        #message("All values are discrete - converting to ordered")
        data.all <- ordered(data.all) # Wird direkt von kde1d geschätzt
      } else {
        #message("Applying equi_jitter to discrete values")
        data.all[disc.ind] <- kde1d::equi_jitter(as.factor(data.all[disc.ind]))
      }
    }
    
    # Konstruktion der Schätzer
    nloc <- length(data.all)
    #message("nloc: ", nloc)
    
    if(estim == "LLE"){
      #message("Using LLE estimator...")
      if(!is.null(ref.start)) {
        #message("Applying reference period weights")
        w <- (1*(year(data.all.zoo) %in% ref.start:ref.end))
      } else {
        w <- numeric(0)
      }
      #message("Calling kde1d...")
      Fhat.pre <- kde1d(x=data.all, xmin = xmin, xmax = xmax, deg = deg, weights = w)
      #message("Calling pkde1d...")
      Fhat <- pkde1d(data.eval, Fhat.pre)
    } else if(estim == "ECDF") {
      #message("Using ECDF estimator...")
      Fhat.pre <- ecdf(data.all)
      # Für skalierung siehe 
      # https://cran.r-project.org/web/packages/SEI/vignettes/SEI_vignette.pdf
      Fhat <- (nloc*Fhat.pre(data.eval) + 1)/(nloc+2)
    } else if(estim == "GPP"){
      #message("Using GPP estimator...")
      order.vec <- rank(data.all)
      Fhat.pre <- (order.vec - 0.44)/(nloc + 0.12)
      Fhat <- approxfun(data.all,Fhat.pre, method = "linear", rule=2)(data.eval)
    }
    
    #message("Fhat summary: ", paste(summary(Fhat), collapse = "; "))
    
    # SPEI berechnen
    #message("Calculating SPEI...")
    spei.out <- qnorm(Fhat)
    #message("SPEI summary: ", paste(summary(spei.out), collapse = "; "))
    
    if(any(is.infinite(spei.out)) & estim == "LLE"){
      #message("Handling infinite SPEI values...")
      #message("Using high-precision calculation with precBits: ", precBits)
      
      # Wir berechnen die CDF selbst und approximieren über negativen wert
      data_check <- mpfr(data.eval[is.infinite(spei.out)], precBits = precBits)
      data.eval_order <- order(data.eval)
      xx <- mpfr(c(0,Fhat.pre$grid_points), precBits = precBits)
      yy <- mpfr(Fhat.pre$values, precBits = precBits)
      Fx <- cumsum(yy * diff(xx))
      Fx <- Fx/max(Fx) # Damit nicht größer als 1
      
      # Wir nehmen die nächste zahl als approximation
      index_check <- sapply(data.eval, function(z)which.min((z-xx[-1])^2 )[1])
      if(precq) {
        #message("Using high-precision qnorm")
        spei.out <- as.numeric(-qnormI(1-Fx[index_check]))
      } else {
        #message("Using standard qnorm")
        spei.out <- -qnorm(as.numeric(1-Fx[index_check]))
      }
      #message("After infinite value handling - SPEI summary: ", paste(summary(spei.out), collapse = "; "))
    }
    
    # Potentiell NA´s einfügen
    if(Na.check) {
      #message("Reinserting NAs...")
      spei.out.cop <- spei.out
      spei.out <- rep(NA, nn)
      spei.out[-data.is.na] <- spei.out.cop
    }
    
    # Auffüllen
    #message("Filling spei.fin with results...")
    spei.fin[index] <- spei.out
  }

  # Umwandeln
  if(is.null(time.frame)) {
    #message("Converting to zoo object...")
    spei.fin <- zoo(spei.fin, as.Date(time(x)))
  }
  
  # Trend anpassen und andere Regressoren
  if(!is.null(formula)){
    #message("Applying formula adjustment...")
    if(formula == "trend") {
      df <- data.frame(y=pnorm(spei.fin), t = seq_along(spei.fin)/length(spei.fin))
      formula <- as.formula(y ~ t)
      uscale <- TRUE
    }
    
    # Regression
    #message("Performing vine regression...")
    vine.pre <- vinereg::vinereg(formula, data = df, selcrit = "aic",
                                 family_set = family_set, uscale = uscale)
    spei.fin <- qnorm(vinereg::cpit(vine.pre, newdata=df))
    spei.fin[is.nan(spei.fin)] <- NA # Damit wie gewohnt NA erscheint
    spei.fin <- zoo(spei.fin, xtime)
  }
  
  #message("===== COMPLETING np.spei FUNCTION =====")
  # Rückgabe
  return(spei.fin)
}

np.spei_batch <- function(data_matrix, freq, ts_start, scale, n_cores=1, ...) {
    # data_matrix: A numeric matrix where rows=time, cols=grid_points
    
    # 1. Setup Time Series Metadata (Do this once for the whole batch)
    ts_start_parts <- as.numeric(strsplit(ts_start, "-")[[1]])
    if(length(ts_start_parts) == 1) ts_start_parts <- c(ts_start_parts, 1)
    
    start_year <- ts_start_parts[1]
    start_month <- ts_start_parts[2]
    start_date <- as.Date(paste0(start_year, "-", sprintf("%02d", start_month), "-01"))
    dates <- seq.Date(from = start_date, by = "month", length.out = nrow(data_matrix))
    
    # 2. Define worker function
    process_column <- function(x_vec) {
        if(all(is.na(x_vec))) {
            return(rep(NA, length(x_vec)))
        }
        # Create zoo object
        x_zoo <- zoo::zoo(x_vec, dates)
        tryCatch({
            res <- np.spei(x = x_zoo, scale = scale, ...)
            return(as.numeric(res))
        }, error = function(e) {
            return(rep(NA, length(x_vec)))
        })
    }

    result_matrix <- apply(data_matrix, 2, process_column)
    
    return(result_matrix)
}