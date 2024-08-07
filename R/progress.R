# The original source for much of this came from Hadley Wickham's dplyr
# code in github.com/tidyverse/dplyr/R/progress.R.
#
# Below is the original license statement for the dplyr package.
#
# The MIT License (MIT)
# =====================
#
#   Copyright © 2013-2015 RStudio and others.
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the “Software”), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
#   The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
#

# changes to these functions by Robert M Flight
# 1. addition of progress_location as a field of the Progress object, argument to
#    initialize, and argument of constructor
# 2. addition of file argument to cat_line function, and all calls to it
# 3. updates to documentation due to new functionality
# 4. removal of decision logic in the Progress$initialize function
# 5. Addition of Progress$finalizer to close file connections that are given

#' Progress bar with estimated time.
#'
#' This provides a reference class representing a text progress bar that displays the
#' estimated time remaining. When finished, it displays the total duration.  The
#' automatic progress bar can be disabled by setting `progress_location = NULL`.
#'
#' @param n Total number of items
#' @param min_time Progress bar will wait until at least `min_time`
#'   seconds have elapsed before displaying any results.
#' @param progress_location where to write the progress to. Default is to make
#' decisions based on location type using `make_kpb_output_decisions()`.
#'
#' @seealso [make_kpb_output_decisions()]
#'
#' @return A ref class with methods `tick()`, `print()`,
#'   `pause()`, and `stop()`.
#' @export
#' @examples
#' p <- progress_estimated(3)
#' p$tick()
#' p$tick()
#' p$tick()
#'
#' p <- progress_estimated(3)
#' for (i in 1:3) p$pause(0.1)$tick()$print()
#'
#' p <- progress_estimated(3)
#' p$tick()$print()$
#'  pause(1)$stop()
#'
#' # If min_time is set, progress bar not shown until that many
#' # seconds have elapsed
#' p <- progress_estimated(3, min_time = 3)
#' for (i in 1:3) p$pause(0.1)$tick()$print()
#'
#' \dontrun{
#' p <- progress_estimated(10, min_time = 3)
#' for (i in 1:10) p$pause(0.5)$tick()$print()
#'
#' # output to stderr
#' p <- progress_estimated(10, progress_location = stderr())
#'
#' # output to a file
#' p <- progress_estimated(10, progress_location = tempfile(fileext = ".log"))
#' }
#'
#' @importFrom R.oo abort
progress_estimated <- function(n, min_time = 0, progress_location = make_kpb_output_decisions()) {
  if (!inherits(n, c("numeric", "integer"))) {
    warning("n is not a number, trying to take the length of n ...")
    n <- length(n)
  }
  if (n <= 1) {
    stop("n must be > 1!")
  }
  Progress$new(n, min_time = min_time, progress_location = progress_location)
}

#' @importFrom R6 R6Class
Progress <- R6::R6Class("Progress",
  public = list(
    n = NULL,
    i = 0,
    init_time = NULL,
    stopped = FALSE,
    stop_time = NULL,
    min_time = NULL,
    last_update = NULL,
    progress_location = NULL,

    initialize = function(n, min_time = 0, progress_location, ...) {
      self$progress_location <- progress_location
      self$n <- n
      self$min_time <- min_time
      self$begin()
    },

    begin = function() {
      "Initialise timer. Call this before beginning timing."
      self$i <- 0
      self$last_update <- self$init_time <- now()
      self$stopped <- FALSE
      self
    },

    pause = function(x) {
      "Sleep for x seconds. Useful for testing."
      Sys.sleep(x)
      self
    },

    width = function() {
      getOption("width") - nchar("|100% ~ 99.9 h remaining") - 2
    },

    tick = function() {
      "Process one element"
      if (self$stopped) return(self)

      if (self$i == self$n) abort("No more ticks")
      self$i <- self$i + 1
      self
    },

    stop = function() {
      if (self$stopped) return(self)

      self$stopped <- TRUE
      self$stop_time <- now()
      self
    },

    print = function(...) {
      if (is.null(self$progress_location)) {
        return(invisible(self))
      }

      if (self$stopped) {
        overall <- show_time(self$stop_time - self$init_time)
        if (self$i == self$n) {
          cat_line(file = self$progress_location, "Completed after ", overall)
          cat("\n")
        } else {
          cat_line(file = self$progress_location, "Killed after ", overall)
          cat("\n")
        }
        return(invisible(self))
      }

      now_ <- now()
      if (now_ - self$init_time < self$min_time || now_ - self$last_update < 0.05) {
        return(invisible(self))
      }
      self$last_update <- now_

      avg <- (now() - self$init_time) / self$i
      time_left <- (self$n - self$i) * avg
      nbars <- trunc(self$i / self$n * self$width())

      cat_line(file = self$progress_location,
        "|", str_rep("=", nbars), str_rep(" ", self$width() - nbars), "|",
        format(round(self$i / self$n * 100), width = 3), "% ",
        "~", show_time(time_left), " remaining"
      )

      invisible(self)
    },

    finalize = function() {
      if (!is.null(self$progress_location)) {
        if (inherits(self$progress_location, "kpblogfile")) {
          close.connection(self$progress_location)
        }
      }

    }

  )
)

cat_line <- function(file = NULL, ...) {
  msg <- paste(..., sep = "", collapse = "")
  gap <- max(c(0, getOption("width") - nchar(msg, "width")))
  cat("\r", msg, rep.int(" ", gap), sep = "", file = file, append = TRUE)
  utils::flush.console()
}

str_rep <- function(x, i) {
  paste(rep.int(x, i), collapse = "")
}

show_time <- function(x) {
  if (x < 60) {
    paste(round(x), "s")
  } else if (x < 60 * 60) {
    paste(round(x / 60), "m")
  } else {
    paste(round(x / (60 * 60)), "h")
  }
}

now <- function() proc.time()[[3]]
