#!/usr/bin/env python

# plugin to check how long since the last update was done
# shamelessly based on check_yum

__author__  = "Hamish Downer"
__title__   = "Nagios Plugin for checking days since last Yum update on RedHat/CentOS systems"
__version__ = "0.0.1"


# Standard Nagios return codes
OK       = 0
WARNING  = 1
CRITICAL = 2
UNKNOWN  = 3

import os
from datetime import date
import sys
import signal
from optparse import OptionParser

DEFAULT_TIMEOUT = 30
DEFAULT_WARNING = 60
DEFAULT_CRITICAL = 90

# python 2.4 datetime does not have the strptime() method
month_to_num = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
        }

def end(status, message):
    """Exits the plugin with first arg as the return code and the second
    arg as the message to output"""
    
    check = ""
    if status == OK:
        print (message)
        sys.exit(OK)
    elif status == WARNING:
        print (message)
        sys.exit(WARNING)
    elif status == CRITICAL:
        print (message)
        sys.exit(CRITICAL)
    else:
        print (message)
        sys.exit(UNKNOWN)


YUM = "/usr/bin/yum"

def check_yum_usable():
    """Checks that the YUM program and path are correct and usable - that
    the program exists and is executable, otherwise exits with error"""

    if not os.path.exists(YUM):
        end(UNKNOWN, "%s cannot be found" % YUM)
    elif not os.path.isfile(YUM):
        end(UNKNOWN, "%s is not a file" % YUM)
    elif not os.access(YUM, os.X_OK):
        end(UNKNOWN, "%s is not executable" % YUM)


class YumUpdateChecker(object):
    def __init__(self):
        """Initialize all object variables"""

        self.timeout            = DEFAULT_TIMEOUT
        self.verbosity          = 0

    def validate_all_variables(self):
        """Validates all object variables to make sure the 
        environment is sane"""

        if self.timeout == None:
            self.timeout = DEFAULT_TIMEOUT
        try:
            self.timeout = int(self.timeout)
        except ValueError:
            end(UNKNOWN, "Timeout must be an whole number, " \
                       + "representing the timeout in seconds")

        if self.timeout < 1 or self.timeout > 3600:
            end(UNKNOWN, "Timeout must be a number between 1 and 3600 seconds")

        if self.warning == None:
            self.warning = DEFAULT_WARNING
        try:
            self.warning = int(self.warning)
        except ValueError:
            end(UNKNOWN, "Warning must be an whole number, " \
                       + "representing the update time limit in days")
        if self.warning < 1 or self.warning > 3650:
            end(UNKNOWN, "Warning must be a number between 1 and 3650 days")

        if self.critical == None:
            self.critical = DEFAULT_CRITICAL
        try:
            self.critical = int(self.critical)
        except ValueError:
            end(UNKNOWN, "Critical must be an whole number, " \
                       + "representing the update time limit in days")
        if self.critical < 1 or self.critical > 3650:
            end(UNKNOWN, "Critical must be a number between 1 and 3650 days")

        if self.warning > self.critical:
            end(UNKNOWN, "Warning cannot be larger than critical")

        if self.exclude == None:
            self.exclude_list = []
        else:
            self.exclude_list = self.exclude.split(',')

        if self.verbosity == None:
            self.verbosity = 0
        try:
            self.verbosity = int(self.verbosity)
            if self.verbosity < 0:
                raise ValueError
        except ValueError:
            end(UNKNOWN, "Invalid verbosity type, must be positive numeric " \
                        + "integer")

    def set_timeout(self):
        """sets an alarm to time out the test"""

        if self.timeout == 1:
            self.vprint(3, "setting plugin timeout to %s second" \
                                                                % self.timeout)
        else:
            self.vprint(3, "setting plugin timeout to %s seconds"\
                                                                % self.timeout)

        signal.signal(signal.SIGALRM, self.sighandler)
        signal.alarm(self.timeout)


    def sighandler(self, discarded, discarded2):
        """Function to be called by signal.alarm to kill the plugin"""

        # Nop for these variables
        discarded = discarded2
        discarded2 = discarded

        end(CRITICAL, "Yum nagios plugin has self terminated after " \
                    + "exceeding the timeout (%s seconds)" % self.timeout)


    def vprint(self, threshold, message):
        """Prints a message if the first arg is numerically greater than the
        verbosity level"""
        if self.verbosity >= threshold:
            print "%s" % message

    def convert_to_past_date(self, date_str):
        """Expect string of form "Mar 12" or "Aug 03" and make it
        either this year, or if this year would be in the future, make
        it last year."""
        year = date.today().year
        month = month_to_num[date_str[:3]]
        day = int(date_str[4:])

        past_date = date(year, month, day)
        if past_date > date.today():
            past_date = date(year-1, month, day)
        return past_date

    def find_last_updated_date(self, logfile):
        if not os.path.exists(logfile):
            self.vprint(1, 'log file %s does not exist' % logfile)
            return None
        if os.path.getsize(logfile) == 0:
            self.vprint(1, 'log file %s has zero length' % logfile)
            return None
        last_date = None
        for line in open(logfile):
            if 'Updated:' in line:
                # might want to exclude some packages
                use_line = True
                for exclude in self.exclude_list:
                    if exclude in line:
                        use_line = False
                if use_line:
                    # date is first 6 characters of line
                    last_date = line[:6]
        if last_date == None:
            self.vprint(1, 'no lines with "Updated:" found in %s' % logfile)
            return None
        # convert date string to actual date
        # should be of form 'Mar 23', 'Jan 04' etc
        self.vprint(3, 'Date found is %s' % last_date)
        return self.convert_to_past_date(last_date)

    def calc_days_ago(self, date):
        datediff = date.today() - date
        return datediff.days

    def check_last_yum_update(self):
        check_yum_usable()
        self.vprint(3, "%s - Version %s\nAuthor: %s\n" \
            % (__title__, __version__, __author__))
        
        self.validate_all_variables()
        self.set_timeout()

        # search for updated in yum.log, or if not found, in yum.log.1
        logdir = '/var/log'
        yum_logs = sorted([f for f in os.listdir(logdir) if f.startswith('yum.log')])
        last_update = None
        for logfile in yum_logs:
            last_update = self.find_last_updated_date(os.path.join(logdir, logfile))
            if last_update:
                break

        if last_update == None:
            # yum never run
            status = CRITICAL
            message = 'No yum log files found, yum probably never run'
        else:
            days_since_update = self.calc_days_ago(last_update)
            if days_since_update == 1:
                message = '1 day since last yum update'
            else:
                message = '<prtg><result><channel>Last Update [days]</channel><value>%d</value></result></prtg>' % days_since_update

            if days_since_update < self.warning:
                status = OK
            elif days_since_update < self.critical:
                status = WARNING
            else:
                status = CRITICAL
        return status, message
            


def main():
    """Parses command line options and calls the test function"""

    update_checker = YumUpdateChecker()
    parser = OptionParser()

    parser.add_option( "-w", 
                       "--warning", 
                       dest="warning",
                       help="Issue WARNING if the last update was more than "  \
                          + "this many days ago.")

    parser.add_option( "-c", 
                       "--critical", 
                       dest="critical",
                       help="Issue CRITICAL if the last update was more than " \
                          + "this many days ago.")

    parser.add_option( "-t",
                       "--timeout",
                       dest="timeout",
                       help="Sets a timeout in seconds after which the "  \
                           +"plugin will exit (defaults to %s seconds). " \
                                                      % DEFAULT_TIMEOUT)
    parser.add_option( "-x", 
                       "--exclude", 
                       dest="exclude",
                       help="List of packages to ignore updates of when " +
                            "checking for last update. (For when you have " +
                            "a small number of packages auto-update.)")

    parser.add_option( "-v", 
                       "--verbose", 
                       action="count", 
                       dest="verbosity",
                       help="Verbose mode. Can be used multiple times to "     \
                          + "increase output. Use -vvv for debugging output. " \
                          + "By default only one result line is printed as "   \
                          + "per Nagios standards")

    parser.add_option( "-V",
                       "--version",
                       action="store_true",
                       dest="version",
                       help="Print version number and exit")

    (options, args) = parser.parse_args()

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    update_checker.warning      = options.warning
    update_checker.critical     = options.critical
    update_checker.exclude      = options.exclude
    update_checker.timeout      = options.timeout
    update_checker.verbosity    = options.verbosity

    if options.version:
        print "%s - Version %s\nAuthor: %s\n" \
            % (__title__, __version__, __author__)
        sys.exit(OK)
    
    result, output = update_checker.check_last_yum_update()
    end(result, output)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print "Caught Control-C..."
        sys.exit(CRITICAL)

# This plugin is based on the check_yum plugin available from
# https://code.google.com/p/check-yum/

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; version 2
# of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.