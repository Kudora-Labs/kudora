package types

func (msg MsgRegisterTenant) ValidateBasic() error {
	if _, err := NormalizeCreator(msg.Creator); err != nil {
		return err
	}
	_, err := NormalizeTenant(msg.Tenant)
	return err
}

func (msg MsgTransferTenantOwnership) ValidateBasic() error {
	creator, err := NormalizeCreator(msg.Creator)
	if err != nil {
		return err
	}
	if _, err := NormalizeTenant(msg.Tenant); err != nil {
		return err
	}
	newOwner, err := NormalizeOwnerAddress(msg.NewOwner, "new owner")
	if err != nil {
		return err
	}
	if creator == newOwner {
		return ErrTenantOwnershipUnchanged.Wrap("new owner must differ from the current owner")
	}
	return nil
}

func (msg MsgAcceptTenantOwnership) ValidateBasic() error {
	if _, err := NormalizeCreator(msg.Creator); err != nil {
		return err
	}
	_, err := NormalizeTenant(msg.Tenant)
	return err
}

func (msg MsgCancelTenantOwnershipTransfer) ValidateBasic() error {
	if _, err := NormalizeCreator(msg.Creator); err != nil {
		return err
	}
	_, err := NormalizeTenant(msg.Tenant)
	return err
}

func (msg MsgCommitIntegritySet) ValidateBasic() error {
	if _, err := NormalizeCreator(msg.Creator); err != nil {
		return err
	}
	if _, err := NormalizeTenant(msg.Tenant); err != nil {
		return err
	}
	if _, err := NormalizeIntegrityType(msg.Type); err != nil {
		return err
	}
	if _, err := NormalizePeriod(msg.Period); err != nil {
		return err
	}
	if _, err := NormalizeRoot(msg.Root); err != nil {
		return err
	}
	_, _, err := PrepareIntegrityRecords(msg.Records)
	return err
}
