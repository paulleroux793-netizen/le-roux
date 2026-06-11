# Shared "predict the visit" helpers: from a patient's booked appointment reason,
# suggest the matching visit-bundle macro(s) so an estimate or treatment plan can
# pre-load itself for review. Used by EstimatesController + CoursesOfTreatmentController.
module VisitSuggestions
  extend ActiveSupport::Concern

  # The patient's next today-or-upcoming, non-cancelled appointment (or nil).
  def next_visit_for(patient)
    patient.appointments
           .where("start_time >= ?", Time.current.beginning_of_day)
           .where.not(status: :cancelled)
           .order(:start_time).first
  end

  # Map a free-text appointment reason to the practice's macro(s) by keyword.
  # Conservative: only well-known visit types; unmatched reasons suggest nothing.
  def suggested_macros_for(reason)
    r = reason.to_s.downcase
    codes = []
    codes += [ "C/U", "C/U & CL" ]             if r =~ /check|exam|recall|\bc\/u\b/
    codes += [ "PROPHY", "C/U & CL" ]          if r =~ /clean|hygiene|scal|prophy|polish/
    codes += [ "C/U" ]                         if r =~ /consult/
    codes += [ "CROWN" ]                       if r =~ /crown/
    codes += [ "BRIDGE 3" ]                    if r =~ /bridge/
    codes += [ "WHITENING" ]                   if r =~ /whiten|bleach/
    codes += [ "VENEER" ]                      if r =~ /veneer/
    codes += [ "F DENTURE" ]                   if r =~ /denture/
    codes += [ "ANT RCT", "POST RCT", "ERCT" ] if r =~ /root canal|\brct\b|endo/
    codes += [ "ALIGNER 1" ]                   if r =~ /aligner|ortho|brace/
    codes += [ "IP PLACE", "IP CROWN" ]        if r =~ /implant/
    codes += [ "RECEMENT" ]                    if r =~ /recement|re-cement/
    return [] if codes.empty?
    TreatmentMacro.active.where(access_code: codes.uniq).order(:access_code).limit(4).to_a
  end
end
