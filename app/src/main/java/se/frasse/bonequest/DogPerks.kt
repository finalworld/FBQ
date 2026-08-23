package se.frasse.bonequest

data class DogPerkInfo(val name:String,val description:String,val bonus:String)

fun dogPerkInfo(id:Int,level:Int):DogPerkInfo {
    val safe=level.coerceIn(1,5)
    return when(id){
        0->DogPerkInfo("Dubbelnos","Ökar chansen att få dubbel belöning från lösa ben.","${safe*2} % chans")
        1->DogPerkInfo("Vandringsglädje","Ger extra XP från godkänd promenadsträcka.","+${safe*5} % promenad-XP")
        2->DogPerkInfo("Bensamlare","Ökar värdet på lösa ben som du plockar upp.","+${safe} ben per fynd")
        3->DogPerkInfo("Grävmästare","Ökar belöningen från jordhögar.","+${safe*5} % högbelöning")
        4->DogPerkInfo("Lång nos","Utökar räckvidden när du plockar upp lösa ben.","+${safe*2} meter")
        5->DogPerkInfo("Spårsinne","Utökar räckvidden för skattjaktsledtrådar.","+${safe*2} meter")
        6->DogPerkInfo("Flitig grävare","Sänker kostnaden för att öppna jordhögar.","-${safe*2} % kostnad")
        7->DogPerkInfo("Butikskompis","Ger rabatt på köp i spelbutiker.","-${safe*2} % pris")
        8->DogPerkInfo("Tursvans","Ökar chansen att hitta en valp i en jordhög.","+${safe} procentenheter")
        else->DogPerkInfo("Sällskapshund","Utökar avståndet där närliggande spelare delar benbelöning.","+${safe*5} meter")
    }
}
