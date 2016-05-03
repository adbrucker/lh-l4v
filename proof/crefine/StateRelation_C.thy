(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory StateRelation_C
imports Wellformed_C
begin

context begin interpretation Arch . (*FIXME: arch_split*)

definition
  "lifth p s \<equiv> the (clift (t_hrs_' s) p)"

definition
  "array_relation r n a c \<equiv> \<forall>i \<le> n. r (a i) (index c (unat i))"

definition 
  "option_to_0 x \<equiv> case x of None \<Rightarrow> 0 | Some y \<Rightarrow> y"

definition
  "option_to_ptr \<equiv> Ptr o option_to_0"

(* used for bound ntfn/tcb *)
definition
  "option_to_ctcb_ptr x \<equiv> case x of None \<Rightarrow> NULL | Some t \<Rightarrow> tcb_ptr_to_ctcb_ptr t"


definition
  byte_to_word_heap :: "(word32 \<Rightarrow> word8) \<Rightarrow> (word32 \<Rightarrow> 10 word \<Rightarrow> word32)"
  where
  "byte_to_word_heap m base off \<equiv> let (ptr :: word32) = base + (ucast off * 4) in
                                       word_rcat [m (ptr + 3), m (ptr + 2), m (ptr + 1), m ptr]"

definition
  heap_to_page_data :: "(word32 \<Rightarrow> kernel_object option) \<Rightarrow> (word32 \<Rightarrow> word8) \<Rightarrow> (word32 \<Rightarrow> (10 word \<Rightarrow> word32) option)"
  where
  "heap_to_page_data hp bhp \<equiv> \<lambda>p. let (uhp :: word32 \<Rightarrow> user_data option) = (projectKO_opt \<circ>\<^sub>m hp) in
                                      option_map (\<lambda>_. byte_to_word_heap bhp p) (uhp p)"

definition
  cmap_relation :: "(word32 \<rightharpoonup> 'a) \<Rightarrow> 'b typ_heap \<Rightarrow> (word32 \<Rightarrow> 'b ptr) \<Rightarrow> ('a \<Rightarrow> 'b \<Rightarrow> bool) \<Rightarrow> bool"
  where
  "cmap_relation as cs addr_fun rel \<equiv> 
          (addr_fun ` (dom as) = dom cs) \<and>
          (\<forall>x \<in> dom as. rel (the (as x)) (the (cs (addr_fun x))))"

definition
  carray_map_relation :: "nat \<Rightarrow> (word32 \<rightharpoonup> ('a :: pre_storable))
    \<Rightarrow> ('b ptr \<Rightarrow> bool) \<Rightarrow> (word32 \<Rightarrow> 'b ptr) \<Rightarrow> bool"
where
  "carray_map_relation bits as cs addr_fun \<equiv>
    (\<forall>p. (is_aligned p bits \<and> (\<forall>p'. p' && ~~ mask bits = p \<and> is_aligned p' (objBits (the (as p')))
        \<longrightarrow> p' \<in> dom as)) \<longleftrightarrow> cs (addr_fun p))"

definition
  cvariable_array_map_relation :: "(word32 \<rightharpoonup> 'a) \<Rightarrow> ('a \<Rightarrow> nat)
    \<Rightarrow> (word32 \<Rightarrow> ('c :: c_type) ptr) \<Rightarrow> heap_typ_desc \<Rightarrow> bool"
where
  "cvariable_array_map_relation amap szs ptrfun htd
    \<equiv> \<forall>p v. amap p = Some v \<longrightarrow> h_t_array_valid htd (ptrfun p) (szs v)"

definition
  asid_map_pd_to_hwasids :: "(asid \<rightharpoonup> hw_asid \<times> obj_ref) \<Rightarrow> (obj_ref \<Rightarrow> hw_asid set)"
where
 "asid_map_pd_to_hwasids mp \<equiv> \<lambda>pd. {hwasid. (hwasid, pd) \<in> ran mp}"

definition
  pd_pointer_to_asid_slot :: "obj_ref \<rightharpoonup> pde_C ptr"
where
 "pd_pointer_to_asid_slot pd \<equiv> if is_aligned pd pdBits then Some (Ptr (pd + 0x3FC0)) else None"

definition
  pde_stored_asid :: "pde_C \<rightharpoonup> hw_asid"
where
 "pde_stored_asid pde \<equiv> if pde_get_tag pde = scast pde_pde_invalid
                             \<and> to_bool (stored_asid_valid_CL (pde_pde_invalid_lift pde))
                        then Some (ucast (stored_hw_asid_CL (pde_pde_invalid_lift pde)))
                        else None"

end

text {*
  Conceptually, the constant armKSKernelVSpace_C resembles ghost state.
  The constant specifies the use of certain address ranges, or ``windows''.
  It is the very nature of these ranges is that they remain fixed
  after initialization.
  Hence, it is not necessary to carry this value around
  as part of the actual state.
  Rather, we simply fix it in a locale for the state relation.

  Note that this locale does not build on @{text kernel}
  but @{text substitute_pre}.
  Hence, we can later base definitions for the ADT on it,
  which can subsequently be instantiated for
  @{text kernel_all_global_addresses} as well as @{text kernel_all_substitute}.
*}
locale state_rel = Arch + substitute_pre +
  fixes armKSKernelVSpace_C :: "machine_word \<Rightarrow> arm_vspace_region_use"

locale kernel = kernel_all_substitute + state_rel

context state_rel
begin

(* relates fixed adresses *)
definition 
  "carch_globals s \<equiv> 
  (armKSGlobalPD s = symbol_table ''armKSGlobalPD'') \<and>
  (armKSGlobalPTs s  = [symbol_table ''armKSGlobalPT'']) \<and>
  (armKSGlobalsFrame s = symbol_table ''armKSGlobalsFrame'')"

definition
  carch_state_relation :: "Arch.kernel_state \<Rightarrow> globals \<Rightarrow> bool"
where
  "carch_state_relation astate cstate \<equiv>
  armKSNextASID_' cstate = armKSNextASID astate \<and>
  armKSKernelVSpace astate = armKSKernelVSpace_C \<and>
  array_relation (op = \<circ> option_to_0) 0xFF (armKSHWASIDTable astate) (armKSHWASIDTable_' cstate) \<and>
  array_relation (op = \<circ> option_to_ptr) (2^asid_high_bits - 1) (armKSASIDTable astate) (armKSASIDTable_' cstate) \<and>
  (asid_map_pd_to_hwasids (armKSASIDMap astate))
       = set_option \<circ> (pde_stored_asid  \<circ>\<^sub>m clift (t_hrs_' cstate) \<circ>\<^sub>m pd_pointer_to_asid_slot) \<and>
  carch_globals astate"

end

context begin interpretation Arch . (*FIXME: arch_split*)

definition
  cmachine_state_relation :: "machine_state \<Rightarrow> globals \<Rightarrow> bool"
where
  "cmachine_state_relation s s' \<equiv> 
  irq_masks s = irq_masks (phantom_machine_state_' s') \<and>
  irq_state s = irq_state (phantom_machine_state_' s') \<and>
  exclusive_state s = exclusive_state (phantom_machine_state_' s') \<and>
  machine_state_rest s = machine_state_rest (phantom_machine_state_' s')"

definition
  "globals_list_id_fudge = id"

type_synonym ('a, 'b) ltyp_heap = "'a ptr \<rightharpoonup> 'b"

abbreviation 
  map_to_tcbs :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> tcb"
  where
  "map_to_tcbs hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_eps :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> endpoint"
  where
  "map_to_eps hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_ntfns :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> notification"
  where
  "map_to_ntfns hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_pdes :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> pde"
  where
  "map_to_pdes hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_ptes :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> pte"
  where
  "map_to_ptes hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_asidpools :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> asidpool"
  where
  "map_to_asidpools hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

abbreviation 
  map_to_user_data :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> word32 \<rightharpoonup> user_data"
  where
  "map_to_user_data hp \<equiv> projectKO_opt \<circ>\<^sub>m hp"

definition
  cmdbnode_relation :: "Structures_H.mdbnode \<Rightarrow> mdb_node_C \<Rightarrow> bool"
where
  "cmdbnode_relation amdb cmdb \<equiv> amdb = mdb_node_to_H (mdb_node_lift cmdb)"

definition
  ccte_relation :: "Structures_H.cte \<Rightarrow> cte_C \<Rightarrow> bool"
where
  "ccte_relation acte ccte \<equiv> Some acte = option_map cte_to_H (cte_lift ccte)
                             \<and> c_valid_cte ccte"

lemma ccte_relation_c_valid_cte: "ccte_relation  c c' \<Longrightarrow> c_valid_cte c'"
  by (simp add: ccte_relation_def)


definition
  tcb_queue_relation' :: "(tcb_C \<Rightarrow> tcb_C ptr) \<Rightarrow> (tcb_C \<Rightarrow> tcb_C ptr) \<Rightarrow> (tcb_C ptr \<Rightarrow> tcb_C option) \<Rightarrow> word32 list \<Rightarrow> tcb_C ptr \<Rightarrow> tcb_C ptr \<Rightarrow> bool"
  where
  "tcb_queue_relation' getNext getPrev hp queue qhead end \<equiv> 
  (end = (if queue = [] then NULL else (tcb_ptr_to_ctcb_ptr (last queue))))
  \<and> tcb_queue_relation getNext getPrev hp queue NULL qhead"

fun
  register_from_H :: "register \<Rightarrow> word32"
  where
  "register_from_H MachineTypes.R0 = scast Kernel_C.R0"
  | "register_from_H MachineTypes.R1 = scast Kernel_C.R1"
  | "register_from_H MachineTypes.R2 = scast Kernel_C.R2"
  | "register_from_H MachineTypes.R3 = scast Kernel_C.R3"
  | "register_from_H MachineTypes.R4 = scast Kernel_C.R4"
  | "register_from_H MachineTypes.R5 = scast Kernel_C.R5"
  | "register_from_H MachineTypes.R6 = scast Kernel_C.R6"
  | "register_from_H MachineTypes.R7 = scast Kernel_C.R7"
  | "register_from_H MachineTypes.R8 = scast Kernel_C.R8"
  | "register_from_H MachineTypes.R9 = scast Kernel_C.R9"
  | "register_from_H MachineTypes.SL = scast Kernel_C.R10" 
  | "register_from_H MachineTypes.FP = scast Kernel_C.R11" 
  | "register_from_H MachineTypes.IP = scast Kernel_C.R12" 
  | "register_from_H MachineTypes.SP = scast Kernel_C.SP"
  | "register_from_H MachineTypes.LR = scast Kernel_C.LR"
  | "register_from_H MachineTypes.LR_svc = scast Kernel_C.LR_svc"
  | "register_from_H MachineTypes.CPSR = scast Kernel_C.CPSR" 
  | "register_from_H MachineTypes.FaultInstruction = scast Kernel_C.FaultInstruction"

definition
  ccontext_relation :: "(MachineTypes.register \<Rightarrow> word32) \<Rightarrow> user_context_C \<Rightarrow> bool"
where
  "ccontext_relation regs uc \<equiv>  \<forall>r. regs r = index (registers_C uc) (unat (register_from_H r))"

primrec
  cthread_state_relation_lifted :: "Structures_H.thread_state \<Rightarrow> 
   (thread_state_CL \<times> fault_CL option) \<Rightarrow> bool"
where
  "cthread_state_relation_lifted (Structures_H.Running) ts'
     = (tsType_CL (fst ts') = scast ThreadState_Running)"
| "cthread_state_relation_lifted (Structures_H.Restart) ts'
     = (tsType_CL (fst ts') = scast ThreadState_Restart)"
| "cthread_state_relation_lifted (Structures_H.Inactive) ts'
     = (tsType_CL (fst ts') = scast ThreadState_Inactive)"
| "cthread_state_relation_lifted (Structures_H.IdleThreadState) ts'
     = (tsType_CL (fst ts') = scast ThreadState_IdleThreadState)"
| "cthread_state_relation_lifted (Structures_H.BlockedOnReply) ts'
     = (tsType_CL (fst ts') = scast ThreadState_BlockedOnReply)"
| "cthread_state_relation_lifted (Structures_H.BlockedOnReceive oref) ts'
     = (tsType_CL (fst ts') = scast ThreadState_BlockedOnReceive \<and>
        oref = blockingObject_CL (fst ts'))"
| "cthread_state_relation_lifted (Structures_H.BlockedOnSend oref badge cg isc) ts'
     = (tsType_CL (fst ts') = scast ThreadState_BlockedOnSend 
        \<and> oref = blockingObject_CL (fst ts') 
        \<and> badge = blockingIPCBadge_CL (fst ts')
        \<and> cg    = to_bool (blockingIPCCanGrant_CL (fst ts'))
        \<and> isc   = to_bool (blockingIPCIsCall_CL (fst ts')))"
| "cthread_state_relation_lifted (Structures_H.BlockedOnNotification oref) ts'
     = (tsType_CL (fst ts') = scast ThreadState_BlockedOnNotification
        \<and> oref = blockingObject_CL (fst ts'))"


definition
  cthread_state_relation :: "Structures_H.thread_state \<Rightarrow> 
  (thread_state_C \<times> fault_C) \<Rightarrow> bool"
where
  "cthread_state_relation \<equiv> \<lambda>a (cs, cf).
  cthread_state_relation_lifted a (thread_state_lift cs, fault_lift cf)"

definition "is_cap_fault cf \<equiv>
  (case cf of (Fault_cap_fault _) \<Rightarrow> True
  | _ \<Rightarrow> False)"

lemma is_cap_fault_simp: "is_cap_fault cf = (\<exists> x. cf=Fault_cap_fault x)"
  by (simp add: is_cap_fault_def split:fault_CL.splits)


definition
  message_info_to_H :: "seL4_MessageInfo_C \<Rightarrow> Types_H.message_info"
  where
  "message_info_to_H mi \<equiv> Types_H.message_info.MI (length_CL (seL4_MessageInfo_lift mi))
                                                  (extraCaps_CL (seL4_MessageInfo_lift mi))
                                                  (capsUnwrapped_CL (seL4_MessageInfo_lift mi))
                                                  (label_CL (seL4_MessageInfo_lift mi))"


fun
  lookup_fault_to_H :: "lookup_fault_CL \<Rightarrow> lookup_failure"
  where
  "lookup_fault_to_H Lookup_fault_invalid_root = InvalidRoot"
  | "lookup_fault_to_H (Lookup_fault_guard_mismatch lf) =
                      (GuardMismatch (unat (bitsLeft_CL lf)) (guardFound_CL lf) (unat (bitsFound_CL lf)))"
  | "lookup_fault_to_H (Lookup_fault_depth_mismatch lf) =
                      (DepthMismatch (unat (lookup_fault_depth_mismatch_CL.bitsLeft_CL lf))
                                     (unat (lookup_fault_depth_mismatch_CL.bitsFound_CL lf)))"
  | "lookup_fault_to_H (Lookup_fault_missing_capability lf) =  
                        (MissingCapability (unat (lookup_fault_missing_capability_CL.bitsLeft_CL lf)))"

fun 
  fault_to_H :: "fault_CL \<Rightarrow> lookup_fault_CL \<Rightarrow> fault option"
where
  "fault_to_H Fault_null_fault lf = None" 
  | "fault_to_H (Fault_cap_fault cf) lf 
           = Some (CapFault (fault_cap_fault_CL.address_CL cf) (to_bool (inReceivePhase_CL cf)) (lookup_fault_to_H lf))"
  | "fault_to_H (Fault_vm_fault vf) lf 
           = Some (VMFault (fault_vm_fault_CL.address_CL vf) [instructionFault_CL vf, FSR_CL vf])"
  | "fault_to_H (Fault_unknown_syscall us) lf 
           = Some (UnknownSyscallException (syscallNumber_CL us))"
  | "fault_to_H (Fault_user_exception ue) lf 
          = Some (UserException (number_CL ue) (code_CL ue))"

definition
  cfault_rel :: "Fault_H.fault option \<Rightarrow> fault_CL option \<Rightarrow> lookup_fault_CL option \<Rightarrow> bool"
where
  "cfault_rel af cf lf \<equiv> \<exists>cf'. cf = Some cf' \<and> 
         (if (is_cap_fault cf') then (\<exists>lf'. lf = Some lf' \<and> fault_to_H cf' lf' = af)
           else (fault_to_H cf' undefined = af))"

definition
  ctcb_relation :: "Structures_H.tcb \<Rightarrow> tcb_C \<Rightarrow> bool"
where
  "ctcb_relation atcb ctcb \<equiv> 
       tcbFaultHandler atcb = tcbFaultHandler_C ctcb 
     \<and> cthread_state_relation (tcbState atcb) (tcbState_C ctcb, tcbFault_C ctcb)
     \<and> tcbIPCBuffer atcb    = tcbIPCBuffer_C ctcb
     \<and> ccontext_relation (tcbContext atcb) (tcbContext_C (tcbArch_C ctcb))
     \<and> tcbQueued atcb       = to_bool (tcbQueued_CL (thread_state_lift (tcbState_C ctcb)))
     \<and> ucast (tcbDomain atcb) = tcbDomain_C ctcb
     \<and> ucast (tcbPriority atcb) = tcbPriority_C ctcb
     \<and> tcbTimeSlice atcb    = unat (tcbTimeSlice_C ctcb)
     \<and> cfault_rel (tcbFault atcb) (fault_lift (tcbFault_C ctcb))
                  (lookup_fault_lift (tcbLookupFailure_C ctcb))
     \<and> option_to_ptr (tcbBoundNotification atcb) = tcbBoundNotification_C ctcb"

abbreviation
  "ep_queue_relation' \<equiv> tcb_queue_relation' tcbEPNext_C tcbEPPrev_C"

definition
  cendpoint_relation :: "tcb_C typ_heap \<Rightarrow> Structures_H.endpoint \<Rightarrow> endpoint_C \<Rightarrow> bool"
where
  "cendpoint_relation h ntfn cep \<equiv>
     let cstate = state_CL (endpoint_lift cep);
         chead  = (Ptr o epQueue_head_CL o endpoint_lift) cep; 
         cend   = (Ptr o epQueue_tail_CL o endpoint_lift) cep in
       case ntfn of
         IdleEP \<Rightarrow> cstate = scast EPState_Idle \<and> ep_queue_relation' h [] chead cend 
       | SendEP q \<Rightarrow> cstate = scast EPState_Send \<and> ep_queue_relation' h q chead cend
       | RecvEP q \<Rightarrow> cstate = scast EPState_Recv \<and> ep_queue_relation' h q chead cend"

definition
  cnotification_relation :: "tcb_C typ_heap \<Rightarrow> Structures_H.notification \<Rightarrow>
                              notification_C \<Rightarrow> bool"
where
  "cnotification_relation h antfn cntfn \<equiv>
     let cntfn'  = notification_lift cntfn;
         cstate = notification_CL.state_CL cntfn';
         chead  = (Ptr o ntfnQueue_head_CL) cntfn';
         cend   = (Ptr o ntfnQueue_tail_CL) cntfn';
         cbound = ((Ptr o ntfnBoundTCB_CL) cntfn' :: tcb_C ptr)
     in
       (case ntfnObj antfn of
         IdleNtfn \<Rightarrow> cstate = scast NtfnState_Idle \<and> ep_queue_relation' h [] chead cend
       | WaitingNtfn q \<Rightarrow> cstate = scast NtfnState_Waiting \<and> ep_queue_relation' h q chead cend
       | ActiveNtfn msgid \<Rightarrow> cstate = scast NtfnState_Active \<and>
                           msgid = ntfnMsgIdentifier_CL cntfn' \<and>
                           ep_queue_relation' h [] chead cend)
       \<and> option_to_ctcb_ptr (ntfnBoundTCB antfn) = cbound"

definition
  "ap_from_vm_rights R \<equiv> case R of 
    VMNoAccess \<Rightarrow> 0
  | VMKernelOnly \<Rightarrow> 1
  | VMReadOnly \<Rightarrow> 2
  | VMReadWrite \<Rightarrow> 3"

definition
  "tex_from_cacheable c \<equiv> case c of
    True \<Rightarrow> 5
  | False \<Rightarrow> 0"

definition 
  "s_from_cacheable c \<equiv> case c of
    True \<Rightarrow> 0
  | False \<Rightarrow> 1"

definition 
  "b_from_cacheable c \<equiv> case c of
    True \<Rightarrow> 1
  | False \<Rightarrow> 0"

definition
  cpde_relation :: "pde \<Rightarrow> pde_C \<Rightarrow> bool"
where
  "cpde_relation pde cpde \<equiv>
  (let cpde' = pde_lift cpde in
  case pde of
    InvalidPDE \<Rightarrow> 
    (\<exists>inv. cpde' = Some (Pde_pde_invalid inv))
  | PageTablePDE frame parity domain \<Rightarrow> 
    cpde' = Some (Pde_pde_coarse 
     \<lparr> pde_pde_coarse_CL.address_CL = frame, 
       P_CL = of_bool parity, 
       Domain_CL = domain \<rparr>)
  | SectionPDE frame parity domain cacheable global xn rights \<Rightarrow> 
    cpde' = Some (Pde_pde_section
     \<lparr> pde_pde_section_CL.address_CL = frame, 
       size_CL = 0, 
       nG_CL = of_bool (~global),
       S_CL = s_from_cacheable cacheable,
       APX_CL = 0,
       TEX_CL = tex_from_cacheable cacheable,
       AP_CL = ap_from_vm_rights rights, 
       P_CL = of_bool parity,
       Domain_CL = domain,
       XN_CL = of_bool xn,
       C_CL = 0,
       B_CL = b_from_cacheable cacheable
  \<rparr>)
  | SuperSectionPDE frame parity cacheable global xn rights \<Rightarrow> 
    cpde' = Some (Pde_pde_section
     \<lparr> pde_pde_section_CL.address_CL = frame, 
       size_CL = 1, 
       nG_CL = of_bool (~global),
       S_CL = s_from_cacheable cacheable,
       APX_CL = 0,
       TEX_CL = tex_from_cacheable cacheable,
       AP_CL = ap_from_vm_rights rights, 
       P_CL = of_bool parity,
       Domain_CL = 0,
       XN_CL = of_bool xn,
       C_CL = 0,
       B_CL = b_from_cacheable cacheable
  \<rparr>))"

definition
  cpte_relation :: "pte \<Rightarrow> pte_C \<Rightarrow> bool"
where
  "cpte_relation pte cpte \<equiv>
  (let cpte' = pte_lift cpte in
  case pte of
    InvalidPTE \<Rightarrow> 
    cpte' = Some (Pte_pte_large
     \<lparr> pte_pte_large_CL.address_CL = 0,
       XN_CL = 0, 
       TEX_CL = 0,
       nG_CL = 0,
       S_CL = 0,
       APX_CL = 0,
       AP_CL = 0,
       C_CL = 0,
       B_CL = 0,
       reserved_CL = 0
     \<rparr>)
  | LargePagePTE frame cacheable global xn rights \<Rightarrow> 
    cpte' = Some (Pte_pte_large
     \<lparr> pte_pte_large_CL.address_CL = frame,
       XN_CL = of_bool xn, 
       TEX_CL = tex_from_cacheable cacheable,
       nG_CL = of_bool (~global),
       S_CL = s_from_cacheable cacheable,
       APX_CL = 0,
       AP_CL = ap_from_vm_rights rights,
       C_CL = 0,
       B_CL = b_from_cacheable cacheable,
       reserved_CL = 1
     \<rparr>)
  | SmallPagePTE frame cacheable global xn rights \<Rightarrow> 
    cpte' = Some (Pte_pte_small
     \<lparr> address_CL = frame,
       nG_CL = of_bool (~global),
       S_CL = s_from_cacheable cacheable,
       APX_CL = 0,
       TEX_CL = tex_from_cacheable cacheable,
       AP_CL = ap_from_vm_rights rights,
       C_CL = 0,
       B_CL = b_from_cacheable cacheable,
       XN_CL = of_bool xn
     \<rparr>))"

(* Invalid PTEs map to large PTEs with reserved bit 0 *)
lemma pte_0:
  "index (pte_C.words_C cpte) 0 = 0 \<Longrightarrow> pte_lift cpte = Some (Pte_pte_large
     \<lparr> pte_pte_large_CL.address_CL = 0,
       XN_CL = 0, 
       TEX_CL = 0,
       nG_CL = 0,
       S_CL = 0,
       APX_CL = 0,
       AP_CL = 0,
       C_CL = 0,
       B_CL = 0,
       reserved_CL = 0
     \<rparr>)"
  by (simp add: pte_lift_def pte_get_tag_def pte_pte_large_def)

definition
  casid_pool_relation :: "asidpool \<Rightarrow> asid_pool_C \<Rightarrow> bool"
where
  "casid_pool_relation asid_pool casid_pool \<equiv> 
  case asid_pool of ASIDPool pool \<Rightarrow>
  case casid_pool of asid_pool_C cpool \<Rightarrow>
  array_relation (op = \<circ> option_to_ptr) (2^asid_low_bits - 1) pool cpool"

definition
  cuser_data_relation :: "(10 word \<Rightarrow> word32) \<Rightarrow> user_data_C \<Rightarrow> bool"
where
  "cuser_data_relation f ud \<equiv> \<forall>off. f off = index (user_data_C.words_C ud) (unat off)"

abbreviation
  "cpspace_cte_relation ah ch \<equiv> cmap_relation (map_to_ctes ah) (clift ch) Ptr ccte_relation"

abbreviation
  "cpspace_tcb_relation ah ch \<equiv> cmap_relation (map_to_tcbs ah) (clift ch) tcb_ptr_to_ctcb_ptr ctcb_relation"

abbreviation
  "cpspace_ep_relation ah ch \<equiv> cmap_relation (map_to_eps ah) (clift ch) Ptr (cendpoint_relation (clift ch))"

abbreviation
  "cpspace_ntfn_relation ah ch \<equiv> cmap_relation (map_to_ntfns ah) (clift ch) Ptr (cnotification_relation (clift ch))"

abbreviation
  "cpspace_pde_relation ah ch \<equiv> cmap_relation (map_to_pdes ah) (clift ch) Ptr cpde_relation"

abbreviation
  "cpspace_pte_relation ah ch \<equiv> cmap_relation (map_to_ptes ah) (clift ch) Ptr cpte_relation"

abbreviation
  "cpspace_asidpool_relation ah ch \<equiv> cmap_relation (map_to_asidpools ah) (clift ch) Ptr casid_pool_relation"

abbreviation
  "cpspace_user_data_relation ah bh ch \<equiv> cmap_relation (heap_to_page_data ah bh) (clift ch) Ptr cuser_data_relation"

abbreviation
  pd_Ptr :: "32 word \<Rightarrow> (pde_C[4096]) ptr" where "pd_Ptr == Ptr"

abbreviation
  "cpspace_pde_array_relation ah ch \<equiv> carray_map_relation pdBits (map_to_pdes ah) (h_t_valid (hrs_htd ch) c_guard) pd_Ptr"

abbreviation
  pt_Ptr :: "32 word \<Rightarrow> (pte_C[256]) ptr" where "pt_Ptr == Ptr"

abbreviation
  "cpspace_pte_array_relation ah ch \<equiv> carray_map_relation ptBits (map_to_ptes ah) (h_t_valid (hrs_htd ch) c_guard) pt_Ptr"


definition
  cpspace_relation :: "(word32 \<rightharpoonup> Structures_H.kernel_object) \<Rightarrow> (word32 \<Rightarrow> word8) \<Rightarrow> heap_raw_state \<Rightarrow> bool"
where
  "cpspace_relation ah bh ch \<equiv>  
  cpspace_cte_relation ah ch \<and> cpspace_tcb_relation ah ch \<and> cpspace_ep_relation ah ch \<and> cpspace_ntfn_relation ah ch \<and>
  cpspace_pde_relation ah ch \<and> cpspace_pte_relation ah ch \<and> cpspace_asidpool_relation ah ch \<and> cpspace_user_data_relation ah bh ch \<and>
  cpspace_pde_array_relation ah ch \<and> cpspace_pte_array_relation ah ch"

abbreviation
  "sched_queue_relation' \<equiv> tcb_queue_relation' tcbSchedNext_C tcbSchedPrev_C"

abbreviation
  end_C :: "tcb_queue_C \<Rightarrow> tcb_C ptr"
where
 "end_C == tcb_queue_C.end_C"

definition
  cready_queues_index_to_C :: "domain \<Rightarrow> priority \<Rightarrow> nat"
where
  "cready_queues_index_to_C qdom prio \<equiv> (unat qdom) * numPriorities + (unat prio)"

definition
  cready_queues_relation :: "tcb_C typ_heap \<Rightarrow> (tcb_queue_C[4096]) \<Rightarrow> (domain \<times> priority \<Rightarrow> ready_queue) \<Rightarrow> bool"
where
  "cready_queues_relation h_tcb queues aqueues \<equiv>
     \<forall>qdom prio. ((qdom \<ge> ucast minDom \<and> qdom \<le> ucast maxDom \<and>
                  prio \<ge> ucast minPrio \<and> prio \<le> ucast maxPrio) \<longrightarrow>
       (let cqueue = index queues (cready_queues_index_to_C qdom prio) in
            sched_queue_relation' h_tcb (aqueues (qdom, prio)) (head_C cqueue) (end_C cqueue)))
        \<and> (\<not> (qdom \<ge> ucast minDom \<and> qdom \<le> ucast maxDom \<and>
                  prio \<ge> ucast minPrio \<and> prio \<le> ucast maxPrio) \<longrightarrow> aqueues (qdom, prio) = [])"


abbreviation
  "cte_array_relation astate cstate
    \<equiv> cvariable_array_map_relation (gsCNodes astate) (\<lambda>n. 2 ^ n)
        cte_Ptr (hrs_htd (t_hrs_' cstate))"

abbreviation
  "tcb_cte_array_relation astate cstate
    \<equiv> cvariable_array_map_relation (map_to_tcbs (ksPSpace astate))
        (\<lambda>x. 5) cte_Ptr (hrs_htd (t_hrs_' cstate))"

fun
  irqstate_to_C :: "irqstate \<Rightarrow> word32"
  where
  "irqstate_to_C IRQInactive = scast Kernel_C.IRQInactive"
  | "irqstate_to_C IRQSignal = scast Kernel_C.IRQSignal"
  | "irqstate_to_C IRQTimer = scast Kernel_C.IRQTimer"


definition
  cinterrupt_relation :: "interrupt_state \<Rightarrow> cte_C ptr \<Rightarrow> (word32[160]) \<Rightarrow> bool"
where
  "cinterrupt_relation airqs cnode cirqs \<equiv>
     cnode = Ptr (intStateIRQNode airqs) \<and>
     (\<forall>irq \<le> (ucast Kernel_C.maxIRQ).
       irqstate_to_C (intStateIRQTable airqs irq) = index cirqs (unat irq))"

definition
  cscheduler_action_relation :: "Structures_H.scheduler_action \<Rightarrow> tcb_C ptr \<Rightarrow> bool"
where
  "cscheduler_action_relation a p \<equiv> case a of
     ResumeCurrentThread \<Rightarrow> p = NULL
   | ChooseNewThread \<Rightarrow> p = Ptr (~~ 0)
   | SwitchToThread p' \<Rightarrow> p = tcb_ptr_to_ctcb_ptr p'"

definition
  dom_schedule_entry_relation :: "8 word \<times> 32 word \<Rightarrow> dschedule_C \<Rightarrow> bool"
where
  "dom_schedule_entry_relation adomSched cdomSched \<equiv>
     ucast (fst adomSched) = dschedule_C.domain_C cdomSched \<and>
     (snd adomSched) = dschedule_C.length_C cdomSched"

definition
  cdom_schedule_relation :: "(8 word \<times> 32 word) list \<Rightarrow> (dschedule_C['b :: finite]) \<Rightarrow> bool"
where
  "cdom_schedule_relation adomSched cdomSched \<equiv>
     length adomSched = card (UNIV :: 'b set) \<and>
     (\<forall>n \<le> length adomSched. dom_schedule_entry_relation (adomSched ! n) (index cdomSched n))"

definition
  ghost_size_rel :: "cghost_state \<Rightarrow> nat \<Rightarrow> bool"
where
  "ghost_size_rel gs maxSize = ((gs_get_assn cap_get_capSizeBits_'proc gs = 0
            \<and> maxSize = card (UNIV :: word32 set))
    \<or> (maxSize > 0 \<and> maxSize = unat (gs_get_assn cap_get_capSizeBits_'proc gs)))"

definition
  cbitmap_L1_relation :: "machine_word['dom::finite] \<Rightarrow> (domain \<Rightarrow> machine_word) \<Rightarrow> bool"
where
  "cbitmap_L1_relation cbitmap1 abitmap1 \<equiv>
    \<forall>d. (d \<le> maxDomain \<longrightarrow> cbitmap1.[unat d] = abitmap1 d) \<and>
        (\<not> d \<le> maxDomain \<longrightarrow> abitmap1 d = 0)"

definition
  cbitmap_L2_relation :: "machine_word['i::finite]['dom::finite]
                          \<Rightarrow> ((domain \<times> nat) \<Rightarrow> machine_word) \<Rightarrow> bool"
where
  "cbitmap_L2_relation cbitmap2 abitmap2 \<equiv>
    \<forall>d i. ((d \<le> maxDomain \<and> i \<le> numPriorities div wordBits)
            \<longrightarrow> cbitmap2.[unat d].[i] = abitmap2 (d, i)) \<and>
           ((\<not> (d \<le> maxDomain \<and> i \<le> numPriorities div wordBits))
            \<longrightarrow>  abitmap2 (d, i) = 0)"

end

definition (in state_rel)
  cstate_relation :: "KernelStateData_H.kernel_state \<Rightarrow> globals \<Rightarrow> bool"
where
  cstate_relation_def:
  "cstate_relation astate cstate \<equiv>
     let cheap = t_hrs_' cstate in
       cpspace_relation (ksPSpace astate) (underlying_memory (ksMachineState astate)) cheap \<and>
       cready_queues_relation (clift cheap)
                             (ksReadyQueues_' cstate)
                             (ksReadyQueues astate) \<and>
       cbitmap_L1_relation (ksReadyQueuesL1Bitmap_' cstate) (ksReadyQueuesL1Bitmap astate) \<and>
       cbitmap_L2_relation (ksReadyQueuesL2Bitmap_' cstate) (ksReadyQueuesL2Bitmap astate) \<and>
       ksCurThread_' cstate = (tcb_ptr_to_ctcb_ptr (ksCurThread astate)) \<and>
       ksIdleThread_' cstate = (tcb_ptr_to_ctcb_ptr (ksIdleThread astate)) \<and>
       cinterrupt_relation (ksInterruptState astate) (intStateIRQNode_' cstate) (intStateIRQTable_' cstate) \<and>
       cscheduler_action_relation (ksSchedulerAction astate)
                                 (ksSchedulerAction_' cstate) \<and>
       carch_state_relation (ksArchState astate) cstate \<and>
       cmachine_state_relation (ksMachineState astate) cstate \<and>
       cte_array_relation astate cstate \<and>
       tcb_cte_array_relation astate cstate \<and>
       apsnd fst (ghost'state_' cstate) = (gsUserPages astate, gsCNodes astate) \<and>
       ghost_size_rel (ghost'state_' cstate) (gsMaxObjectSize astate) \<and>
       ksWorkUnitsCompleted_' cstate = ksWorkUnitsCompleted astate \<and>
       h_t_valid (hrs_htd (t_hrs_' cstate)) c_guard
         (ptr_coerce (intStateIRQNode_' cstate) :: (cte_C[256]) ptr) \<and>
       {ptr_val (intStateIRQNode_' cstate) ..+ 2 ^ (8 + cte_level_bits)} \<subseteq> kernel_data_refs \<and>
       h_t_valid (hrs_htd (t_hrs_' cstate)) c_guard
         (pd_Ptr (symbol_table ''armKSGlobalPD'')) \<and>
       ptr_span (pd_Ptr (symbol_table ''armKSGlobalPD'')) \<subseteq> kernel_data_refs \<and>
       htd_safe domain (hrs_htd (t_hrs_' cstate)) \<and>
       kernel_data_refs = (- domain) \<and>
       globals_list_distinct (- kernel_data_refs) symbol_table globals_list \<and>
       cdom_schedule_relation (ksDomSchedule astate)
                              Kernel_C.kernel_all_global_addresses.ksDomSchedule \<and>
       ksDomScheduleIdx_' cstate = of_nat (ksDomScheduleIdx astate) \<and>
       ksCurDomain_' cstate = ucast (ksCurDomain astate) \<and>
       ksDomainTime_' cstate = ksDomainTime astate"

definition
  ccap_relation :: "capability \<Rightarrow> cap_C \<Rightarrow> bool"
where
  "ccap_relation acap ccap \<equiv> (Some acap = option_map cap_to_H (cap_lift ccap))
                             \<and> (c_valid_cap ccap)"

lemma ccap_relation_c_valid_cap: "ccap_relation  c c' \<Longrightarrow> c_valid_cap c'"
  by (simp add: ccap_relation_def)

fun
  fault_to_fault_tag :: "fault \<Rightarrow> word32"
  where
  "fault_to_fault_tag (CapFault a b c) = scast fault_cap_fault"
  | "fault_to_fault_tag (VMFault a b)  = scast fault_vm_fault"
  | "fault_to_fault_tag (UnknownSyscallException a) = scast fault_unknown_syscall"
  | "fault_to_fault_tag (UserException a b) = scast fault_user_exception"


(* Return relations *)

record errtype =
  errfault :: "fault_CL option"
  errlookup_fault :: "lookup_fault_CL option"
  errsyscall :: syscall_error_C

primrec
  lookup_failure_rel :: "lookup_failure \<Rightarrow> word32 \<Rightarrow> errtype \<Rightarrow> bool"
where
  "lookup_failure_rel InvalidRoot fl es = (fl = scast EXCEPTION_LOOKUP_FAULT \<and> errlookup_fault es = Some Lookup_fault_invalid_root)"
| "lookup_failure_rel (GuardMismatch bl gf sz) fl es = (fl = scast EXCEPTION_LOOKUP_FAULT \<and> 
    (\<exists>lf. errlookup_fault es = Some (Lookup_fault_guard_mismatch lf) \<and>
          guardFound_CL lf = gf \<and> unat (bitsLeft_CL lf) = bl \<and> unat (bitsFound_CL lf) = sz))"
| "lookup_failure_rel (DepthMismatch bl bf) fl es = (fl = scast EXCEPTION_LOOKUP_FAULT \<and> 
    (\<exists>lf. errlookup_fault es = Some (Lookup_fault_depth_mismatch lf) \<and>
          unat (lookup_fault_depth_mismatch_CL.bitsLeft_CL lf) = bl 
        \<and> unat (lookup_fault_depth_mismatch_CL.bitsFound_CL lf) = bf))"
| "lookup_failure_rel (MissingCapability bl) fl es = (fl = scast EXCEPTION_LOOKUP_FAULT \<and> 
    (\<exists>lf. errlookup_fault es = Some (Lookup_fault_missing_capability lf) \<and>
          unat (lookup_fault_missing_capability_CL.bitsLeft_CL lf) = bl))"


definition
  syscall_error_to_H :: "syscall_error_C \<Rightarrow> lookup_fault_CL option \<Rightarrow> syscall_error option"
where
 "syscall_error_to_H se lf \<equiv>
    if type_C se = scast seL4_InvalidArgument
         then Some (InvalidArgument (unat (invalidArgumentNumber_C se)))
    else if type_C se = scast seL4_InvalidCapability
         then Some (InvalidCapability (unat (invalidCapNumber_C se)))
    else if type_C se = scast seL4_IllegalOperation then Some IllegalOperation
    else if type_C se = scast seL4_RangeError
         then Some (RangeError (rangeErrorMin_C se) (rangeErrorMax_C se))
    else if type_C se = scast seL4_AlignmentError then Some AlignmentError
    else if type_C se = scast seL4_FailedLookup
         then option_map (FailedLookup (to_bool (failedLookupWasSource_C se))
                           o lookup_fault_to_H) lf
    else if type_C se = scast seL4_TruncatedMessage then Some TruncatedMessage
    else if type_C se = scast seL4_DeleteFirst then Some DeleteFirst
    else if type_C se = scast seL4_RevokeFirst then Some RevokeFirst
    else if type_C se = scast seL4_NotEnoughMemory then Some (NotEnoughMemory (memoryLeft_C se)) 
    else None"

lemmas syscall_error_type_defs
    = seL4_AlignmentError_def seL4_DeleteFirst_def seL4_FailedLookup_def
      seL4_IllegalOperation_def seL4_InvalidArgument_def seL4_InvalidCapability_def
      seL4_NotEnoughMemory_def seL4_RangeError_def seL4_RevokeFirst_def
      seL4_TruncatedMessage_def

lemma
  syscall_error_to_H_cases:
 "type_C se = scast seL4_InvalidArgument
     \<Longrightarrow> syscall_error_to_H se lf = Some (InvalidArgument (unat (invalidArgumentNumber_C se)))"
 "type_C se = scast seL4_InvalidCapability
     \<Longrightarrow> syscall_error_to_H se lf =  Some (InvalidCapability (unat (invalidCapNumber_C se)))"
 "type_C se = scast seL4_IllegalOperation
     \<Longrightarrow> syscall_error_to_H se lf = Some IllegalOperation"
 "type_C se = scast seL4_RangeError
     \<Longrightarrow> syscall_error_to_H se lf = Some (RangeError (rangeErrorMin_C se) (rangeErrorMax_C se))"
 "type_C se = scast seL4_AlignmentError
     \<Longrightarrow> syscall_error_to_H se lf = Some AlignmentError"
 "type_C se = scast seL4_FailedLookup
     \<Longrightarrow> syscall_error_to_H se lf =  option_map (FailedLookup (to_bool (failedLookupWasSource_C se))
                           o lookup_fault_to_H) lf"
 "type_C se = scast seL4_TruncatedMessage
     \<Longrightarrow> syscall_error_to_H se lf = Some TruncatedMessage"
 "type_C se = scast seL4_DeleteFirst
     \<Longrightarrow> syscall_error_to_H se lf = Some DeleteFirst"
 "type_C se = scast seL4_RevokeFirst
     \<Longrightarrow> syscall_error_to_H se lf = Some RevokeFirst"
 "type_C se = scast seL4_NotEnoughMemory
     \<Longrightarrow> syscall_error_to_H se lf = Some (NotEnoughMemory (memoryLeft_C se))"
  by (simp add: syscall_error_to_H_def syscall_error_type_defs)+

definition
  syscall_error_rel :: "syscall_error \<Rightarrow> word32 \<Rightarrow> errtype \<Rightarrow> bool" where
 "syscall_error_rel se fl es \<equiv> fl = scast EXCEPTION_SYSCALL_ERROR
                                 \<and> syscall_error_to_H (errsyscall es) (errlookup_fault es)
                                       = Some se"

(* cap rights *)
definition
  "cap_rights_to_H rs \<equiv> CapRights (to_bool (capAllowWrite_CL rs))
                                  (to_bool (capAllowRead_CL rs))
                                  (to_bool (capAllowGrant_CL rs))"

definition
  "ccap_rights_relation cr cr' \<equiv> cr = cap_rights_to_H (cap_rights_lift cr')"

lemma (in kernel) syscall_error_to_H_cases_rev:
  "\<And>n. syscall_error_to_H e lf = Some (InvalidArgument n) \<Longrightarrow>
        type_C e = scast seL4_InvalidArgument"
  "\<And>n. syscall_error_to_H e lf = Some (InvalidCapability n) \<Longrightarrow>
        type_C e = scast seL4_InvalidCapability"
  "syscall_error_to_H e lf = Some IllegalOperation \<Longrightarrow>
        type_C e = scast seL4_IllegalOperation"
  "\<And>w1 w2. syscall_error_to_H e lf = Some (RangeError w1 w2) \<Longrightarrow>
        type_C e = scast seL4_RangeError"
  "syscall_error_to_H e lf = Some AlignmentError \<Longrightarrow>
        type_C e = scast seL4_AlignmentError"
  "\<And>b lf'. syscall_error_to_H e lf = Some (FailedLookup b lf') \<Longrightarrow>
        type_C e = scast seL4_FailedLookup"
  "syscall_error_to_H e lf = Some TruncatedMessage \<Longrightarrow>
        type_C e = scast seL4_TruncatedMessage"
  "syscall_error_to_H e lf = Some DeleteFirst \<Longrightarrow>
        type_C e = scast seL4_DeleteFirst"
  "syscall_error_to_H e lf = Some RevokeFirst \<Longrightarrow>
        type_C e = scast seL4_RevokeFirst"
  by (clarsimp simp: syscall_error_to_H_def syscall_error_type_defs
              split: split_if_asm)+

definition 
  syscall_from_H :: "syscall \<Rightarrow> word32"
where
  "syscall_from_H c \<equiv> case c of 
    SysSend \<Rightarrow> scast Kernel_C.SysSend
  | SysNBSend \<Rightarrow> scast Kernel_C.SysNBSend
  | SysCall \<Rightarrow> scast Kernel_C.SysCall
  | SysRecv \<Rightarrow> scast Kernel_C.SysRecv
  | SysReply \<Rightarrow> scast Kernel_C.SysReply
  | SysReplyRecv \<Rightarrow> scast Kernel_C.SysReplyRecv
  | SysNBRecv \<Rightarrow> scast Kernel_C.SysNBRecv
  | SysYield \<Rightarrow> scast Kernel_C.SysYield"

lemma (in kernel) cmap_relation_cs_atD:
  "\<lbrakk> cmap_relation as cs addr_fun rel; cs (addr_fun x) = Some y; inj addr_fun \<rbrakk> \<Longrightarrow>
  \<exists>ko. as x = Some ko \<and> rel ko y"
  apply (clarsimp simp: cmap_relation_def)
  apply (subgoal_tac "x \<in> dom as")
   apply (drule (1) bspec)
   apply (clarsimp simp: dom_def)
  apply (subgoal_tac "addr_fun x \<in> addr_fun ` dom as")
   prefer 2
   apply fastforce
  apply (erule imageE) 
  apply (drule (1) injD)
  apply simp
  done

end
